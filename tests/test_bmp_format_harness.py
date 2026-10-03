"""Independent, source-only BMP admission and fail-closed harness tests.

Process/compiler checks are mocked. Synthetic observations test protocol and
planning only; they are never accepted as native differential evidence.
"""
import copy
from contextlib import ExitStack
import hashlib
import io
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import bmp_format_probe as p
from bmp_probe import (bitmap, bitmap16, bitfield_bitmap, indexed_bitmap,
                       core_bitmap, core_indexed_bitmap, fixtures as legacy_fixtures)


def tiny(channels=3, extended=False):
    return dict(id='tiny', width=1, height=1, channels=channels,
                bytes=bitmap(1, 1, [0x11121314], bpp=channels*8), extended=extended)


def native_rows(cases):
    # Deliberately synthetic, independent complete protocol rows for plumbing.
    return [dict(p.meta(a['case'], a['role']),
                 bytes=[17]*(a['case']['width']*a['case']['height']*
                             (4 if a['role']=='normalized' else a['case']['channels'])))
            for a in p.native_actions(cases)]


def unit_actions(count=1):
    return [dict(case=dict(tiny(), id='unit-'+str(i)), role='raw',
                 expected=dict(p.meta(dict(tiny(), id='unit-'+str(i)), 'raw'), bytes=[17,18,19]),
                 normalized=[17,18,19,255]) for i in range(count)]


def lanes_for(partitions):
    return {lane: dict(passed=False, batches=[dict(entry, bytes=entry['compared_bytes'], passed=True)
                                            for entry in partitions], differences=[]) for lane in p.LANES}


def encoded(action, values):
    return '\n'.join(json.dumps(v) for v in [p.meta(action['case'], action['role']),
                                             *[values[i:i+256] for i in range(0,len(values),256)], 'end'])+'\n'


def flags():
    return 'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY -DSUPPORT_FILEFORMAT_BMP\n'


def cache():
    return '\n'.join(k+':STRING='+v for k,v in dict(PLATFORM='Memory', CMAKE_BUILD_TYPE='Release',
        CUSTOMIZE_BUILD='ON', SUPPORT_FILEFORMAT_BMP='ON', SUPPORT_MODULE_RAUDIO='OFF',
        BUILD_EXAMPLES='OFF', USE_EXTERNAL_GLFW='OFF').items())+'\n'


def altered(data, offset, fmt, value):
    result=bytearray(data)
    struct.pack_into('<'+fmt, result, offset, value)
    return list(result)


class BmpRunnerTests(unittest.TestCase):

    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.work=Path(self.tmp.name);p.SEALED.clear()

    def tearDown(self):p.SEALED.clear();self.tmp.cleanup()

    def test_seal_rejects_changed_missing_and_resealing(self):
        path=self.work/'source';path.write_text('one');p.seal(path);p.verify_sealed();path.write_text('two')
        with self.assertRaises(ValueError):p.verify_sealed()
        with self.assertRaises(ValueError):p.seal(path)
        path.unlink()
        with self.assertRaises(ValueError):p.verify_sealed()

    def test_record_success_retains_environment_command_and_streams(self):
        fake=subprocess.CompletedProcess(['tool'],0,'ok\n','warning\n');env={'ONLY':'native'};receipt={'policy':'clean-loader'}
        with patch.object(p,'run_process_group',return_value=fake) as run:
            self.assertEqual(p.record_run(['tool'],self.work,'success',environment=env,receipt=receipt,require_output=True),'ok\n')
        self.assertEqual(run.call_args.kwargs['env'],env)
        row=json.loads((self.work/'success.command.json').read_text());self.assertEqual(row['reference_environment'],receipt);self.assertEqual(row['exit_code'],0)
        self.assertEqual(row['timeout_seconds'],600);self.assertIs(type(row['elapsed_seconds']),float);self.assertGreaterEqual(row['elapsed_seconds'],0)
        self.assertEqual((self.work/'success.stderr').read_text(),'warning\n');p.verify_sealed()

    def test_failed_native_exit_empty_output_and_missing_compiler_output(self):
        for name,result,command,require in [('failed',subprocess.CompletedProcess([],9,'partial','bad'),['tool'],False),('empty',subprocess.CompletedProcess([],0,'',''),['tool'],True),('compiler',subprocess.CompletedProcess([],0,'ok',''),['tool','-o',str(self.work/'out')],False)]:
            with self.subTest(name=name),patch.object(p,'run_process_group',return_value=result),self.assertRaises(ValueError):p.record_run(command,self.work,name,require_output=require)
            self.assertTrue((self.work/(name+'.command.json')).is_file())

    def test_stale_compiler_output_cannot_be_reused(self):
        path=self.work/'out';path.write_text('stale')
        with patch.object(p,'run_process_group',return_value=subprocess.CompletedProcess([],0,'','')),self.assertRaises(ValueError):p.record_run(['compiler','-o',path],self.work,'stale')
        self.assertFalse(path.exists())

    def test_timeout_retains_failed_receipt_and_partial_streams(self):
        error=subprocess.TimeoutExpired(['tool'],1,output=b'partial',stderr=b'waiting')
        with patch.object(p,'run_process_group',side_effect=error),self.assertRaises(ValueError):p.record_run(['tool'],self.work,'timeout',timeout=1)
        row=json.loads((self.work/'timeout.command.json').read_text());self.assertTrue(row['timed_out']);self.assertIsNone(row['exit_code'])
        self.assertEqual(row['timeout_seconds'],1);self.assertIs(type(row['elapsed_seconds']),float);self.assertGreaterEqual(row['elapsed_seconds'],0)
        self.assertEqual((self.work/'timeout.stdout').read_text(),'partial');self.assertEqual((self.work/'timeout.stderr').read_text(),'waiting')

    def test_stale_report_reset_before_invalid_arguments(self):
        target=self.work/'report';target.mkdir();path=target/'results.json';path.write_text('{"passed":true}')
        with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(['--build-dir',str(target),'--bad'])
        self.assertFalse(json.loads(path.read_text())['passed'])

    def test_all_duplicate_destinations_reset_and_exact_token_classification(self):
        a=self.work/'a';b=self.work/'b'
        for dest in (a,b):dest.mkdir();(dest/'results.json').write_text('{"passed":true}')
        self.assertEqual(p.admit_directories(['--build-dir',str(a),'--build-dir='+str(b)]),b.resolve())
        self.assertFalse(json.loads((a/'results.json').read_text())['passed']);self.assertFalse(json.loads((b/'results.json').read_text())['passed'])
        self.assertEqual(p.report_directories(['--build-di',str(a)]),[p.BUILD/'bmp-format-probe'])
        self.assertEqual(p.report_directories(['--','--build-dir',str(a)]),[p.BUILD/'bmp-format-probe'])

    def test_mandatory_lanes_complete_contiguous_typed_and_nonempty(self):
        actions=unit_actions();partitions=p.plan_partitions(actions);lanes=lanes_for(partitions)
        good=copy.deepcopy(lanes);p.finish_lanes(good,actions,partitions);self.assertTrue(all(v['passed'] for v in good.values()))
        variants=[]
        for key,value in [('start',False),('start',1),('count',True),('count',0),('count',33),('passed',False)]:
            bad=copy.deepcopy(lanes);bad['cpu-1']['batches'][0][key]=value;variants.append(bad)
        bad=copy.deepcopy(lanes);del bad['javascript'];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-2']['differences']=[{}];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-2']['batches']=[];variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):p.finish_lanes(bad,actions,partitions)
        with self.assertRaises(ValueError):p.finish_lanes(lanes,[],[])

    def test_native_build_explicit_bmp_and_configuration_checked_before_execution(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();commands=[]
        def record(command,work,label,**kwargs):
            commands.append(list(map(str,command)))
            if label=='configure':
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(cache());(directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(flags().replace(' -DSUPPORT_FILEFORMAT_BMP',''))
        with self.assertRaises(ValueError):p.native_archive(args,self.work,record)
        self.assertEqual(len(commands),1);self.assertIn('-DSUPPORT_FILEFORMAT_BMP=ON',commands[0]);self.assertIn('-DCUSTOMIZE_BUILD=ON',commands[0])


class BmpFailureEvidenceTests(unittest.TestCase):

    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.work=Path(self.tmp.name);p.SEALED.clear()

    def tearDown(self):p.SEALED.clear();self.tmp.cleanup()

    def test_failed_and_timedout_compiler_outputs_are_sealed(self):
        for timeout in (False,True):
            p.SEALED.clear();output=self.work/('timedout' if timeout else 'failed')
            def run(*args,**kwargs):
                output.write_bytes(b'partial compiler bytes')
                if timeout:raise subprocess.TimeoutExpired(['compiler'],1,output='partial',stderr='timeout')
                return subprocess.CompletedProcess([],9,'partial','error')
            with patch.object(p,'run_process_group',side_effect=run),self.assertRaises(ValueError):p.record_run(['compiler','-o',output],self.work,output.name)
            self.assertIn(str(output.resolve()),p.SEALED);p.verify_sealed()
            receipt=json.loads((self.work/(output.name+'.command.json')).read_text())
            self.assertEqual(receipt['artifacts'][str(output)],p.digest(output))
            output.write_bytes(b'drift')
            with self.assertRaises(ValueError):p.verify_sealed()

    def test_native_build_refuses_preexisting_directory(self):
        (self.work/'raylib-build').mkdir();args=type('Args',(),dict(raylib_source=self.work/'source'))()
        with self.assertRaises(ValueError):p.native_archive(args,self.work,lambda *a,**k:self.fail('Stale native build attempted'))

    def test_loader_clean_children_parent_unchanged_and_receipt_checked(self):
        import os
        from reference_environment import LOADER_NAMES
        with patch.dict(os.environ,{name:'qualification-parent' for name in LOADER_NAMES}):
            before=dict(os.environ);environment=p.ReferenceEnvironment('clean-loader')
            child=environment.child();self.assertTrue(all(name not in child for name in LOADER_NAMES))
            self.assertEqual(dict(os.environ),before);environment.assert_receipt(environment.receipt())
            receipt=environment.receipt();receipt['policy']='inherited'
            with self.assertRaises(ValueError):environment.assert_receipt(receipt)
            os.environ[LOADER_NAMES[0]]='changed'
            with self.assertRaises(ValueError):environment.assert_unchanged()

    def test_startup_failure_retains_sealed_receipt_and_streams(self):
        with patch.object(p,'run_process_group',side_effect=FileNotFoundError('tool absent')),self.assertRaises(ValueError):p.record_run(['missing'],self.work,'startup')
        receipt=json.loads((self.work/'startup.command.json').read_text())
        self.assertEqual(receipt['startup_error'],'FileNotFoundError');self.assertIsNone(receipt['exit_code'])
        self.assertIn('tool absent',(self.work/'startup.stderr').read_text());p.verify_sealed()

    def test_runtime_failure_retains_partial_report_and_durable_seals(self):
        target=self.work/'report';target.mkdir();report=target/'results.json'
        def failing(argv):
            report.write_text(json.dumps(dict(passed=False,lanes={'cpu-1':{'passed':False}},phase='native')))
            path=self.work/'partial';path.write_text('observed bytes');p.seal(path)
            raise ValueError('native failed')
        with patch.object(p,'run_probe',side_effect=failing),self.assertRaises(ValueError):p.main(['--build-dir',str(target)])
        result=json.loads(report.read_text());self.assertFalse(result['passed']);self.assertEqual(result['phase'],'native')
        self.assertEqual(result['failure'],dict(type='ValueError',message='native failed'))
        self.assertEqual(result['sealed_artifacts'][str((self.work/'partial').resolve())],p.digest(self.work/'partial'))
        self.assertIn('cpu-1',result['lanes'])

    def test_malformed_or_missing_runtime_reports_replace_stale_success(self):
        target=self.work/'malformed-report';target.mkdir();report=target/'results.json'
        for content in ('', '{"passed":true', '{"passed":true,"passed":true}', '[]', 'null', 'true', None):
            with self.subTest(content=content):
                report.write_text('{"passed":true}')
                def failing(argv):
                    if content is None:report.unlink()
                    else:report.write_text(content)
                    raise ValueError('original runtime failure')
                with patch.object(p,'run_probe',side_effect=failing),self.assertRaisesRegex(ValueError,'original runtime failure'):
                    p.main(['--build-dir',str(target)])
                result=json.loads(report.read_text())
                self.assertIs(result['passed'],False)
                self.assertEqual(result['failure'],dict(type='ValueError',message='original runtime failure'))
                self.assertEqual(result['sealed_artifacts'],dict(p.SEALED))

    def test_native_archive_success_seals_config_and_compiler_before_build(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();labels=[];compiler=self.work/'compiler';compiler.write_text('compiler')
        def record(command,work,label,**kwargs):
            labels.append(label)
            if label=='configure':
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeFiles/version').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(cache());(directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(flags())
                (directory/'CMakeFiles/version/CMakeCCompiler.cmake').write_text('set(CMAKE_C_COMPILER "'+str(compiler)+'")\nset(CMAKE_C_COMPILER_ID "Clang")\nset(CMAKE_C_COMPILER_VERSION "1")\n')
            elif label=='native-build':
                self.assertIn(str(compiler.resolve()),p.SEALED)
                self.assertIn(str((work/'raylib-build/CMakeCache.txt').resolve()),p.SEALED)
                (work/'raylib-build/raylib/libraylib.a').write_bytes(b'archive')
            return 'compiler version 1'
        archive,receipt=p.native_archive(args,self.work,record)
        self.assertEqual(labels,['configure','archive-compiler-version','native-build'])
        self.assertEqual(receipt['mode'],'fresh-isolated-build');self.assertEqual(receipt['artifacts'][str(archive)],p.digest(archive));p.verify_sealed()

    def test_finish_lanes_does_not_mark_partial_success(self):
        actions=unit_actions();partitions=p.plan_partitions(actions);lanes=lanes_for(partitions)
        lanes['javascript']['batches']=[]
        with self.assertRaises(ValueError):p.finish_lanes(lanes,actions,partitions)
        self.assertTrue(all(row['passed'] is False for row in lanes.values()))


class BmpPartitionTests(unittest.TestCase):

    def test_empty_actions_invalid_budget_empty_program_and_oversized_singleton_reject(self):
        with self.assertRaises(ValueError):p.plan_partitions([])
        for budget in (0,-1,True,1.0,p.SOURCE_BYTE_LIMIT+1):
            with self.subTest(budget=budget),self.assertRaises(ValueError):p.plan_partitions(unit_actions(),budget)
        with patch.object(p,'candidate_program',return_value=''),self.assertRaises(ValueError):p.plan_partitions(unit_actions())
        with patch.object(p,'candidate_program',side_effect=lambda actions:'x'*(10 if actions[0]['case']['id']=='unit-0' else p.SOURCE_BYTE_LIMIT+1)),self.assertRaises(ValueError):p.plan_partitions(unit_actions(33))
        with patch.object(p,'candidate_program',return_value='x'*(p.SOURCE_BYTE_LIMIT+1)),self.assertRaisesRegex(ValueError,'singleton'):p.plan_partitions(unit_actions())

    def test_max32_is_preserved_and_planning_is_deterministic(self):
        actions=unit_actions(65);first=p.plan_partitions(actions);self.assertEqual(first,p.plan_partitions(copy.deepcopy(actions)))
        self.assertEqual([(b['start'],b['count']) for b in first],[(0,32),(32,32),(64,1)])
        p.validate_partitions(actions,first)
        self.assertEqual(sum(b['compared_bytes'] for b in first),65*3)

    def test_utf8_source_cap_exact_boundary_and_greedy_order(self):
        actions=unit_actions(5)
        with patch.object(p,'candidate_program',side_effect=lambda selected:'é'*len(selected)):
            plan=p.plan_partitions(actions,4)
            self.assertEqual([(b['start'],b['count'],b['source_bytes']) for b in plan],[(0,2,4),(2,2,4),(4,1,2)])
            p.validate_partitions(actions,plan,4)
            with self.assertRaises(ValueError):p.plan_partitions(actions,1)
        with patch.object(p,'candidate_program',return_value='x'*p.SOURCE_BYTE_LIMIT):
            plan=p.plan_partitions(unit_actions());self.assertEqual(plan[0]['source_bytes'],p.SOURCE_BYTE_LIMIT)

    def test_plan_rejects_empty_missing_extra_gap_overlap_type_hash_and_budget_drift(self):
        actions=unit_actions(33);plan=p.plan_partitions(actions);variants=[[],plan[:-1],plan+plan,plan[::-1]]
        for key,value in [('start',True),('start',1),('count',False),('count',0),('count',33),('source_bytes',True),('source_bytes',0),('source_bytes',p.SOURCE_BYTE_LIMIT+1),('source_sha256','0'*64),('actions_sha256','0'*64),('compared_bytes',True),('compared_bytes',0),('extra',1)]:
            bad=copy.deepcopy(plan);bad[0][key]=value;variants.append(bad)
        for start in (31,33):
            bad=copy.deepcopy(plan);bad[1]['start']=start;variants.append(bad)
        for bad in variants:
            with self.subTest(plan=bad[:1]),self.assertRaises(ValueError):p.validate_partitions(actions,bad)

    def test_action_order_identity_and_full_content_preserved(self):
        actions=unit_actions(3);plan=p.plan_partitions(actions)
        variants=[actions[::-1],actions[:2],actions+[actions[0]]]
        for target,key,value in [('case','id','different'),('case','bytes',[0]),('expected','bytes',[18])]:
            changed=copy.deepcopy(actions);changed[0][target][key]=value;variants.append(changed)
        changed=copy.deepcopy(actions);changed[0]['normalized']=[0,0,0,0];variants.append(changed)
        for changed in variants:
            with self.assertRaises(ValueError):p.validate_partitions(changed,plan)
        # A role that does not render its expected bytes still seals those bytes.
        changed=copy.deepcopy(actions);changed[0]['expected']['bytes']=[18]
        self.assertEqual(p.candidate_program(actions),p.candidate_program(changed))
        self.assertNotEqual(p.action_digest(actions),p.action_digest(changed))
        with self.assertRaises(ValueError):p.validate_partitions(changed,plan)

    def test_lane_receipts_must_match_every_planned_batch_and_full_byte_totals(self):
        actions=unit_actions(33);plan=p.plan_partitions(actions);lanes=lanes_for(plan)
        p.finish_lanes(lanes,actions,plan);self.assertTrue(all(row['passed'] for row in lanes.values()))
        for key,value in [('source_bytes',1),('source_sha256','0'*64),('actions_sha256','0'*64),('compared_bytes',0),('bytes',0),('bytes',True),('passed',1)]:
            changed=lanes_for(plan);changed['javascript']['batches'][0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):p.finish_lanes(changed,actions,plan)
            self.assertTrue(all(row['passed'] is False for row in changed.values()))
        changed=lanes_for(plan);changed['cpu-1']['batches'].reverse()
        with self.assertRaises(ValueError):p.finish_lanes(changed,actions,plan)
        changed=lanes_for(plan);changed['cpu-2']['batches'].append(changed['cpu-2']['batches'][0])
        with self.assertRaises(ValueError):p.finish_lanes(changed,actions,plan)


class BmpProcessGroupTests(unittest.TestCase):

    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.work=Path(self.tmp.name);p.SEALED.clear()

    def tearDown(self):p.SEALED.clear();self.tmp.cleanup()

    def test_cleanup_drain_timeout_is_bounded_closes_pipes_and_reaps_only_owned_leader(self):
        process=MagicMock(pid=123456,returncode=None)
        process.communicate.side_effect=[subprocess.TimeoutExpired(['tool'],600,output=b'first',stderr=b'warning'),subprocess.TimeoutExpired(['tool'],5,output=b'complete partial',stderr=b'warning')]
        def reaped(*args,**kwargs):process.returncode=-signal.SIGKILL;return process.returncode
        process.wait.side_effect=reaped
        with patch.object(p.subprocess,'Popen',return_value=process) as launch,patch.object(p.os,'killpg') as kill,patch.object(p.time,'monotonic',side_effect=[10,10.2,15.1,15.2]):
            with self.assertRaises(subprocess.TimeoutExpired) as failure:p.run_process_group(['tool'],cwd=self.work,env={'ONLY':'child'},timeout=600)
        self.assertTrue(launch.call_args.kwargs['start_new_session']);self.assertEqual(launch.call_args.kwargs['env'],{'ONLY':'child'})
        kill.assert_called_once_with(process.pid,signal.SIGKILL)
        self.assertEqual(process.communicate.call_args_list[0].kwargs['timeout'],600)
        self.assertLessEqual(process.communicate.call_args_list[1].kwargs['timeout'],p.PROCESS_CLEANUP_SECONDS)
        self.assertEqual(process.wait.call_args.kwargs['timeout'],0)
        process.stdout.close.assert_called_once();process.stderr.close.assert_called_once()
        self.assertEqual(failure.exception.process_stdout,b'complete partial');self.assertTrue(failure.exception.process_group_receipt['leader_reaped'])
        self.assertIn('TimeoutExpired',failure.exception.process_group_receipt['cleanup_error'])

    def test_interruption_cleans_owned_group_and_keeps_durable_receipts(self):
        process=MagicMock(pid=123457,returncode=-signal.SIGKILL)
        process.communicate.side_effect=[KeyboardInterrupt(),('partial','diagnostic')]
        with patch.object(p.subprocess,'Popen',return_value=process),patch.object(p.os,'killpg') as kill:
            with self.assertRaises(KeyboardInterrupt):p.record_run(['tool'],self.work,'interrupt',timeout=600)
        kill.assert_called_once_with(process.pid,signal.SIGKILL)
        row=json.loads((self.work/'interrupt.command.json').read_text())
        self.assertEqual(row['communication_error'],'KeyboardInterrupt');self.assertTrue(row['leader_reaped'])
        self.assertEqual((self.work/'interrupt.stdout').read_text(),'partial');self.assertEqual((self.work/'interrupt.stderr').read_text(),'diagnostic');p.verify_sealed()


class BmpProtocolTests(unittest.TestCase):
    def setUp(self):
        self.case=tiny(); self.action=dict(case=self.case, role='raw'); self.row=p.meta(self.case, 'raw')

    def text(self, row=None, parts=None):
        return '\n'.join(json.dumps(v) for v in [self.row if row is None else row,
            *([[17,18,19], 'end'] if parts is None else parts)])+'\n'

    def test_complete_rgb_rgba_raw_roundtrip_alias_and_normalized(self):
        for channels in (3,4):
            case=tiny(channels)
            for role in ('raw','raw-roundtrip','factory','owner','alias-BMP','normalized','bridge','surface'):
                action=dict(case=case,role=role)
                count=channels if role in p.RAW_ROLES else 4
                values=list(range(17,17+count))
                row=p.parse_rows(encoded(action,values),[action])[0]
                self.assertEqual(row,dict(p.meta(case,role),bytes=values))
                self.assertEqual(row['format'],(4 if channels==3 else 7) if role in p.RAW_ROLES else 7)

    def test_nonfinite_and_duplicate_json_rejected_recursively(self):
        for value in ('NaN','Infinity','-Infinity','[NaN]','{"ignored":Infinity}','1e999','[-1e999]',
                      '{"width":1,"width":1}','{"x":{"format":4,"format":7}}'):
            with self.subTest(value=value),self.assertRaises(ValueError):p.strict_json(value)
        with self.assertRaises(ValueError):
            p.parse_rows(self.text().replace('"width": 1','"width": 1,"width": 1'),[self.action])

    def test_exact_metadata_fields_types_order_and_roles(self):
        for key,value in [('id','other'),('role','bridge'),('width',2),('height',2),('format',7),
                          ('mipmaps',2),('width',True),('height',1.0),('mipmaps',True),
                          ('format',4.0),('format',1),('format',2),('extra',0)]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                p.parse_rows(self.text(dict(self.row,**{key:value})),[self.action])
        for key in self.row:
            row=self.row.copy();del row[key]
            with self.subTest(missing=key),self.assertRaises(ValueError):p.parse_rows(self.text(row),[self.action])
        normal=dict(case=self.case,role='normalized')
        with self.assertRaises(ValueError):
            p.parse_rows(self.text()+encoded(normal,[17,18,19,255]),[normal,self.action])
        with self.assertRaises(ValueError):p.meta(self.case,'rejected')

    def test_empty_missing_extra_blank_duplicate_and_malformed_frames(self):
        variants=['',self.text().replace('"end"\n',''),self.text()+self.text(),
                  self.text()+'"end"\n','\n'+self.text(),self.text()+'\n','{}\n','null\n']
        variants += [self.text(parts=parts) for parts in
                     (['end'],[[],'end'],[[17,18],'end'],[[17,18,19,20],'end'],[[0]*257,'end'],
                      [None],[[True,18,19],'end'],[[17.0,18,19],'end'],[[256,18,19],'end'],
                      [[-1,18,19],'end'],[[17,18,19],False],[[17,18,19],'END'],[[17,18,19],{}])]
        for text in variants:
            with self.subTest(text=text[:70]),self.assertRaises(ValueError):p.parse_rows(text,[self.action])
        with self.assertRaises(ValueError):p.parse_rows('',[])

    def test_full_chunk_boundaries_and_rejected_early_short_chunk(self):
        case=dict(self.case,width=171);action=dict(case=case,role='raw');data=[i%256 for i in range(513)]
        self.assertEqual(p.parse_rows(encoded(action,data),[action])[0]['bytes'],data)
        for chunks in ([data[:1],data[1:257],data[257:]], [data[:255],data[255:511],data[511:]],
                       [data[:256],data[256:512],[],data[512:]]):
            text='\n'.join(json.dumps(v) for v in [p.meta(case,'raw'),*chunks,'end'])
            with self.assertRaises(ValueError):p.parse_rows(text,[action])

    def test_error_roles_exact_typed_not_image_frames(self):
        control=p.controls()[0]
        for role in ('formatted-error','surface-error'):
            action=dict(case=control,role=role);row=dict(id=control['id'],role=role,error=control['error'])
            self.assertEqual(p.parse_rows(json.dumps(row),[action]),[row])
            for key,value in [('error',99),('error',True),('error',0.0),('extra',0),('role','raw')]:
                with self.subTest(role=role,key=key,value=value),self.assertRaises(ValueError):
                    p.parse_rows(json.dumps(dict(row,**{key:value})),[action])
            with self.assertRaises(ValueError):p.parse_rows(json.dumps(row)+'\n"end"',[action])
            with self.assertRaises(ValueError):p.parse_rows(json.dumps(dict(row,role='other-error')),[action])

    def test_every_difference_and_lengths_are_retained(self):
        expected=[dict(self.row,bytes=[1,2,3]),dict(self.row,bytes=[4,5,6])]
        actual=[dict(self.row,bytes=[9,2,8]),dict(self.row,bytes=[4,0])]
        delta=p.differences(expected,actual)
        self.assertEqual([[d['index'] for d in row['byte_differences']] for row in delta],[[0,2],[1]])
        self.assertEqual((delta[1]['expected_length'],delta[1]['actual_length']),(3,2))
        with self.assertRaises(ValueError):p.differences(expected,actual[:1])


class BmpAdmissionTests(unittest.TestCase):
    def test_all_98_legacy_inputs_and_46_controls_are_byte_exact(self):
        cases=p.fixtures();controls=p.controls();accepted,invalid,_=legacy_fixtures()
        self.assertEqual((len(accepted),len(invalid)),(98,46))
        by_id={c['id']:c for c in cases};bad_by_id={c['id']:c for c in controls}
        self.assertEqual(len(by_id),len(cases));self.assertEqual(len(bad_by_id),len(controls))
        self.assertGreater(len(cases),98);self.assertGreater(len(controls),46)
        for case in accepted:
            observed=by_id['legacy-'+case['id']]
            self.assertEqual(observed['bytes'],case['bytes'])
            info=p.inspect_header(observed['bytes'])
            self.assertEqual(tuple(observed[k] for k in ('width','height','channels')),
                             tuple(info[k] for k in ('width','height','channels')))
        for control in invalid:
            self.assertEqual(bad_by_id['legacy-'+control['id']],dict(control,id='legacy-'+control['id']))
        p.validate_cases(cases);p.validate_controls(controls)

    def test_channels_follow_effective_alpha_not_depth_or_opacity(self):
        vectors=[(bitmap(1,1,[0x01020300],bpp=32),4),
                 (bitmap(1,1,[0x010203ff],bpp=32),4),
                 (bitmap(1,1,[0x01020300]),3),
                 (bitmap16(1,1,[0xffff]),3)]
        for dib in (40,56):
            for bits in (16,32):
                vectors.append((bitfield_bitmap(1,1,[0],bpp=bits,dib=dib,
                                masks=(0xf800,0x7e0,0x1f,0xff000000)),3))
        for dib in (108,124):
            for compression in (0,3):
                for alpha in (0,0x8000,0xff000000):
                    vectors.append((bitfield_bitmap(1,1,[0],bpp=16,dib=dib,
                                    masks=(0x7c00,0x3e0,0x1f,alpha),compression=compression),4 if alpha else 3))
        for data,channels in vectors:
            with self.subTest(dib=data[14],bpp=data[28],channels=channels):
                self.assertEqual(p.inspect_header(data)['channels'],channels)

    def test_rgb32_zero_alpha_repair_flag_is_layout_semantics(self):
        for dib in (40,56,108,124):
            for word in (0,0x00102030,0xff102030):
                info=p.inspect_header(bitfield_bitmap(1,1,[word],bpp=32,dib=dib,compression=0))
                self.assertEqual(info['effective_masks'],[0xff0000,0xff00,0xff,0xff000000])
                self.assertEqual(info['channels'],4);self.assertIs(info['repair_zero_alpha'],True)
        for dib in (108,124):
            for bits in (16,32):
                info=p.inspect_header(bitfield_bitmap(1,1,[0],bpp=bits,dib=dib,
                                                     masks=(31,992,31744,32768),compression=3))
                self.assertEqual(info['channels'],4);self.assertIs(info['repair_zero_alpha'],False)

    def test_ignored_rgb_and_56_embedded_masks_do_not_select_format(self):
        for dib in (56,108,124):
            for bits in (16,24,32):
                data=bitfield_bitmap(1,1,[0],bpp=bits,dib=dib,compression=0,masks=(0,0,0,0))
                if dib==56:data[54:70]=[255]*16
                elif bits!=16:data[54:70]=[255]*16
                info=p.inspect_header(data)
                self.assertEqual(info['channels'],4 if bits==32 else 3)
                self.assertEqual(info['effective_masks'][3],0xff000000 if bits==32 else 0)
        data=bitfield_bitmap(1,1,[0],dib=56,masks=(31,992,31744,0))
        data[54:70]=[255]*16
        info=p.inspect_header(data)
        self.assertEqual(info['effective_masks'],[31,992,31744,0]);self.assertEqual(info['header_bytes'],82)

    def test_palette_reserved_and_clr_used_never_select_alpha(self):
        for dib in (40,56,108,124):
            for bits in (1,4,8):
                for alpha in (0,1,127,255):
                    data=indexed_bitmap(2,1,[0,1],[0x01020300|alpha,0x10203000|alpha],
                                        bpp=bits,dib=dib,colors_used=0xffffffff)
                    info=p.inspect_header(data)
                    self.assertEqual(info['channels'],3);self.assertEqual(info['palette_count'],2)
                    self.assertEqual(info['palette_entry_bytes'],4)
        for bits in (1,4,8):
            info=p.inspect_header(core_indexed_bitmap(2,1,[0,1],[0,0xffffffff],bpp=bits))
            self.assertEqual(info['channels'],3);self.assertEqual(info['palette_entry_bytes'],3)

    def test_core_palette_count_and_native_skip_all_remainders(self):
        for bits in (1,4,8):
            for remainder in range(3):
                data=core_indexed_bitmap(1,1,[0],[0x01020300],bpp=bits,remainder=remainder)
                info=p.inspect_header(data)
                self.assertEqual(info['palette_count'],1)
                self.assertEqual(info['palette_skip'],12+remainder)
                self.assertEqual(info['payload_offset'],41+remainder)
                self.assertEqual(info['raster_bytes'],4)
        bad=altered(core_indexed_bitmap(1,1,[0],[0],bpp=8),10,'I',29)
        with self.assertRaises(ValueError):p.inspect_header(bad)

    def test_double_gap_payload_boundary_and_all_padding_widths(self):
        for bits in (16,24,32):
            for width in range(1,5):
                for gap in (0,1,3,1024):
                    data=bitfield_bitmap(width,2,[0]*(width*2),bpp=bits,compression=0,gap=gap)
                    info=p.inspect_header(data)
                    row=width*(bits//8);stride=(row+3)&~3
                    self.assertEqual((info['row_bytes'],info['stride'],info['padding']),(row,stride,stride-row))
                    self.assertEqual(info['payload_offset'],54+2*gap)
                    self.assertEqual(info['gap'],gap);self.assertEqual(info['raster_bytes'],stride*2)
                    with self.assertRaises(ValueError):p.inspect_header(data[:-1])
        data=bitmap(1,1,[0],gap=4)
        with self.assertRaises(ValueError):p.inspect_header(data[:-4])
        info=p.inspect_header(core_bitmap(1,1,[0],gap=1024))
        self.assertEqual(info['payload_offset'],26+2048)

    def test_indexed_gap_once_indices_checked_unused_bits_ignored(self):
        for bits in (1,4,8):
            for dib in (40,56,108,124):
                for gap in range(4):
                    data=indexed_bitmap(1,2,[0,0],[0x12345678],bpp=bits,dib=dib,gap=gap)
                    info=p.inspect_header(data)
                    self.assertEqual(info['palette_count'],1);self.assertEqual(info['palette_skip'],gap)
                    self.assertEqual(info['payload_offset'],14+dib+4+gap)
                    # Encoder fills unused bits with ones; those cannot become extra indices.
                    self.assertEqual(info['channels'],3)
                    at=info['payload_offset'];data[at]|=1<<(8-bits)
                    with self.assertRaises(ValueError):p.inspect_header(data)
        data=indexed_bitmap(2,2,[0,0,0,1],[0],bpp=4)
        with self.assertRaises(ValueError):p.inspect_header(data)

    def test_every_required_prefix_and_control_rejected_before_native(self):
        vectors=[bitmap(1,1,[0]),bitmap(1,1,[0],bpp=32,dib=108),
                 bitfield_bitmap(1,1,[0],dib=40),bitfield_bitmap(1,1,[0],dib=56),
                 bitfield_bitmap(1,1,[0],dib=124),core_bitmap(1,1,[0]),
                 indexed_bitmap(1,1,[0],[0]),core_indexed_bitmap(1,1,[0],[0])]
        for data in vectors:
            p.inspect_header(data)
            for size in range(len(data)):
                with self.subTest(dib=data[14],size=size),self.assertRaises(ValueError):p.inspect_header(data[:size])
        for control in p.controls():
            with self.subTest(control=control['id']),self.assertRaises(ValueError):p.inspect_header(control['bytes'])
        with self.assertRaises(ValueError):p.reference_program(p.controls())

    def test_entire_byte_domain_includes_ignored_header_gap_padding_tail(self):
        data=bitfield_bitmap(1,1,[0],dib=124,gap=3)+[1,2,3]
        for index in range(len(data)):
            for value in (256,-1,True,1.0):
                bad=data.copy();bad[index]=value
                with self.subTest(index=index,value=value),self.assertRaises(ValueError):p.inspect_header(bad)
        for data in (None,(),b'BM',bytearray(b'BM'),[0]*13):
            with self.assertRaises(ValueError):p.inspect_header(data)

    def test_header_dimension_compression_masks_and_offset_fail_closed(self):
        base=bitmap(1,1,[0])
        for offset,fmt,values in [(0,'H',(0,0x4d41)),(14,'I',(0,16,52,64,125)),
                                  (26,'H',(0,2)),(28,'H',(0,2,15,17,48)),
                                  (30,'I',(1,2,3,4,5,6)),(18,'I',(0,4097,0xffffffff)),
                                  (22,'I',(0,4097,0x80000000)),(10,'I',(0,53,1079,0xffffffff))]:
            for value in values:
                with self.subTest(offset=offset,value=value),self.assertRaises(ValueError):
                    p.inspect_header(altered(base,offset,fmt,value))
        for masks in ((0,31,992,0),(0x1ff,31,992,0),(31,992,31744,0x1ff)):
            with self.assertRaises(ValueError):p.inspect_header(bitfield_bitmap(1,1,[0],dib=108,masks=masks))
        for dib in (40,56):
            with self.assertRaises(ValueError):p.inspect_header(bitfield_bitmap(1,1,[0],dib=dib,masks=(31,31,31,0)))
        # Identical masks are accepted in V4/V5, as are overlap and noncontiguity.
        for dib in (108,124):
            for masks in ((31,31,31,0),(5,10,0x50,0xa000),(0xff,0xf0,0xff00,0xf)):
                self.assertIn(p.inspect_header(bitfield_bitmap(1,1,[0],bpp=32,dib=dib,masks=masks))['channels'],(3,4))

    def test_file_size_reserved_profile_words_and_complete_tail_are_ignored(self):
        base=bitfield_bitmap(1,1,[0],dib=124)
        expected=p.inspect_header(base)
        for offset,fmt in ((2,'I'),(6,'H'),(8,'H'),(34,'I'),(38,'I'),(42,'I'),(46,'I'),
                           (50,'I'),(122,'I'),(126,'I'),(130,'I'),(134,'I')):
            changed=altered(base,offset,fmt,(1<<(struct.calcsize(fmt)*8))-1)
            self.assertEqual(p.inspect_header(changed),expected)
        # Harness safety budgets are separate from the unchanged memory API.
        large=base+[0]*(1_048_577-len(base))
        observed=p.inspect_header(large)
        self.assertEqual(observed['tail_bytes'],len(large)-len(base))
        p.validate_cases([dict(tiny(),id='large-tail',bytes=large,channels=3)])

    def test_native_declarations_exact_types_ids_and_budgets(self):
        case=tiny()
        for change in (dict(width=0),dict(width=4097),dict(width=True),dict(height=1.0),dict(channels=4),
                       dict(extended=1),dict(id='unsafe"id'),dict(bytes=case['bytes'][:-1]),dict(extra=True)):
            with self.subTest(change=change),self.assertRaises(ValueError):p.validate_cases([dict(case,**change)])
        for key in case:
            bad=case.copy();del bad[key]
            with self.assertRaises(ValueError):p.validate_cases([bad])
        for cases in ([],[case,case],p.controls()[:1]):
            with self.assertRaises(ValueError):p.validate_cases(cases)
        with patch.object(p,'MAX_TOTAL_BYTES',1),self.assertRaises(ValueError):p.validate_cases([case])
        with self.assertRaises(ValueError):p.inspect_header(bitmap(4096,4096,[0]))

    def test_fixture_budgets_do_not_become_api_errors_or_one_mib_caps(self):
        # Complete 1024x342 RGB raster exceeds 1 MiB while staying in the API's
        # independent 1..4096 axis domain. No candidate/native execution occurs.
        data=bitmap(1024,342,[0]*(1024*342))
        self.assertGreater(len(data),1_048_576)
        with self.assertRaises(ValueError):p.inspect_header(data)
        info=p.inspect_header(data,fixture_budget=False)
        self.assertEqual((info['width'],info['height'],info['channels']),(1024,342,3))
        with self.assertRaisesRegex(ValueError,'mislabeled'):
            p.validate_controls([dict(id='valid-large-raster',bytes=data,error=2)])

    def test_added_fixture_shapes_orientations_alpha_discriminators_and_ramps(self):
        by_id={case['id']:case for case in p.fixtures()}
        for channels in (3,4):
            for name,width,height in [('single',1,1),('padded',3,5),('axis-row',4096,1),
                                      ('axis-column',1,4096),('moderate',81,63)]:
                case=by_id[f'c{channels}-{name}']
                self.assertEqual((case['width'],case['height'],case['channels']),(width,height,channels))
                info=p.inspect_header(case['bytes'])
                self.assertIs(info['top'],True)
                if width*height>1:self.assertGreater(len(set(case['bytes'][info['payload_offset']:])),10)
        for dib in (40,56,108,124):
            for name in ('zero','opaque','mixed'):
                self.assertEqual(by_id[f'rgb32-{dib}-alpha-{name}']['channels'],4)
        for dib in (108,124):
            for name in ('zero','opaque','mixed','above-word'):
                self.assertEqual(by_id[f'rgb16-{dib}-alpha-{name}']['channels'],4)
            self.assertEqual(by_id[f'rgb16-{dib}-alpha-absent']['channels'],3)
        case=by_id['c4-alpha-ramp'];info=p.inspect_header(case['bytes']);payload=case['bytes'][info['payload_offset']:]
        self.assertEqual(set(payload[3::4]),set(range(256)))

    def test_checked_error_precedence_remains_explicit_and_native_excluded(self):
        by_id={case['id']:case for case in p.controls()}
        for name,error in [('bad-byte-before-header',1),('bad-byte-before-size',1),('bad-byte-before-padding',1),
                           ('bad-header-before-size',0),('bad-offset-before-size',0),('bad-size-before-truncated',2),
                           ('bad-size-before-incomplete-masks',2),('bad-size-before-invalid-mask',2),
                           ('truncated-before-invalid-index',3)]:
            self.assertEqual(by_id[name]['error'],error)
        controls=list(by_id.values())
        with self.assertRaises(ValueError):p.reference_program(controls)

    def test_control_schema_and_accepted_input_mislabeled_reject(self):
        control=p.controls()[0]
        for change in (dict(error=True),dict(error=5),dict(bytes=[-1]),dict(bytes=[True]),dict(extra=1)):
            with self.subTest(change=change),self.assertRaises(ValueError):p.validate_controls([dict(control,**change)])
        with self.assertRaises(ValueError):p.validate_controls([dict(id='accepted',bytes=tiny()['bytes'],error=3)])
        with self.assertRaises(ValueError):p.validate_controls([control,control])

class BmpNativeAndOwnershipTests(unittest.TestCase):
    def test_native_raw_is_observed_before_normalization_and_alias_reload(self):
        for channels in (3,4):
            case=tiny(channels,extended=True);program=p.reference_program([case])
            self.assertLess(program.index('"raw",image)'),program.index('ImageFormat(&image,7)'))
            self.assertLess(program.index('ImageFormat(&image,7)'),program.index('"normalized",image)'))
            for suffix in ('.bmp','.BMP'):self.assertIn('LoadImageFromMemory("'+suffix+'"',program)
            for token in ('if(!little_endian())','image.mipmaps!=1',f'image.format!={p.FORMATS[channels]}',
                          f'GetPixelDataSize(image.width,image.height,image.format)!={channels}',
                          'GetPixelDataSize(image.width,image.height,image.format)!=4'):
                self.assertIn(token,program)
            self.assertEqual(program.count('Image image=LoadImageFromMemory'),1)
            self.assertEqual(program.count('image=LoadImageFromMemory'),2)
            self.assertNotIn('LoadImageColors',program);self.assertNotIn('stbi_load',program)
            self.assertEqual([a['role'] for a in p.native_actions([case])],['raw','normalized','alias-BMP'])

    def test_native_cache_and_actual_flags_both_required_and_unambiguous(self):
        self.assertEqual(p.validate_native_config(cache(),flags())['SUPPORT_FILEFORMAT_BMP'],'ON')
        commented='// Generated cache\n\n'+'\n// option\n'.join(cache().splitlines())+'\n'
        self.assertEqual(p.validate_native_config(commented,flags())['PLATFORM'],'Memory')
        with self.assertRaises(ValueError):p.validate_native_config(cache()+'PLATFORM:STRING=Memory\n',flags())
        for macro in ('SUPPORT_FILEFORMAT_BMP','EXTERNAL_CONFIG_FLAGS','PLATFORM_MEMORY'):
            self.assertEqual(p.validate_native_config(cache(),flags().replace('-D'+macro,'-D '+macro+'=1'))['PLATFORM'],'Memory')
            for broken in (flags().replace(' -D'+macro,''),flags()+' -D'+macro,flags()+' -U'+macro,
                           flags()+' -U '+macro,flags()+' -D '+macro+'=0',flags().replace('-D'+macro,'-D'+macro+'=0')):
                with self.subTest(macro=macro,flags=broken),self.assertRaises(ValueError):
                    p.validate_native_config(cache(),broken)
        for broken in (flags()+' -DPLATFORM_DESKTOP',flags()+' -D',flags()+' -U', '# '+flags()):
            with self.assertRaises(ValueError):p.validate_native_config(cache(),broken)
        for old,new in [('BMP:STRING=ON','BMP:STRING=OFF'),('CUSTOMIZE_BUILD:STRING=ON','CUSTOMIZE_BUILD:STRING=OFF'),
                        ('PLATFORM:STRING=Memory','PLATFORM:STRING=Desktop'),('CMAKE_BUILD_TYPE:STRING=Release','CMAKE_BUILD_TYPE:STRING=Debug')]:
            with self.assertRaises(ValueError):p.validate_native_config(cache().replace(old,new),flags())

    def test_native_qualification_requires_exact_typed_routing_proof(self):
        row=dict(little_endian=True,bmp_enabled=True,effective_alpha_routing=True,formats=[4,7])
        self.assertEqual(p.qualification(json.dumps(row)),row)
        for key,value in [('little_endian',False),('bmp_enabled',False),('effective_alpha_routing',1),
                          ('formats',[4.0,7]),('formats',[4,True]),('formats',[7,4]),('formats',[4]),('extra',True)]:
            with self.subTest(key=key),self.assertRaises(ValueError):p.qualification(json.dumps(dict(row,**{key:value})))
        for text in ('',json.dumps(row)+'\n'+json.dumps(row),'[]','null'):
            with self.assertRaises(ValueError):p.qualification(text)
        for key in row:
            incomplete=row.copy();del incomplete[key]
            with self.assertRaises(ValueError):p.qualification(json.dumps(incomplete))
        self.assertIn('uint16_t word=1',p.QUALIFY);self.assertIn('if(!little_endian())return 10',p.QUALIFY)
        self.assertIn('image.format!=4',p.QUALIFY);self.assertIn('image.format!=7',p.QUALIFY)

    def test_candidate_raw_factory_roundtrip_highbits_and_retained_owner_routes(self):
        for channels in (3,4):
            case=tiny(channels,extended=True);rows=native_rows([case])
            actions,_=p.candidate_actions([case],p.controls()[:1],rows);program=p.candidate_program(actions)
            for token in ('word <= 16777215','U32.is_eq(format, 7)','+format: U32','(pixels, +word)',
                          'J.Image.Formatted.decode_bmp','J.Image.Formatted.to_surface','J.Surface.to_formatted',
                          'J.Image.Formatted.from_bytes','J.Image.Formatted.get','J.Surface.decode_bmp',
                          'J.Surface.decode_image(','J.UncontractedDecode{}','J.FusedDecode{}',
                          'J.Image.Formatted.export(image)','owner.read(result, 0, 0, Some{first})',
                          'def roundtrip.bytes(values: List<U32>, bytes: +List<U32>) -> +List<U32>:',
                          'J.Image.Formatted.from_bytes(width, height, format, roundtrip.bytes(bytes, Nil{}))',
                          'roundtrip.exported(J.Image.Formatted.export(image))',
                          '(width - 1 : U32)','4294967295, 0, None{}','0, 4294967295, None{}',
                          'formatted.error(J.Image.Formatted.decode_bmp','surface.error(J.Surface.decode_bmp'):
                self.assertIn(token,program)
            self.assertIn(f'J.Image.Formatted.from_bytes(1, 1, {p.FORMATS[channels]},',program)
            self.assertNotIn('Image.Formatted.convert',program)
            roles=[a['role'] for a in actions]
            self.assertEqual(set(roles),{'raw','raw-roundtrip','bridge','surface','factory','owner',
                                         'dispatch-bmp','dispatch-BMP','uncontracted','fused','formatted-error','surface-error'})
            for action in actions:
                if action['role'] in p.RAW_ROLES:self.assertEqual(action['expected']['bytes'],rows[0]['bytes'])
                elif 'bytes' in action['expected']:self.assertEqual(action['expected']['bytes'],rows[1]['bytes'])
            rows[-1]['bytes']=[18]*channels
            with self.assertRaises(ValueError):p.candidate_actions([case],[],rows)

    def test_candidate_revalidates_native_full_order_metadata_and_payload(self):
        case=tiny();rows=native_rows([case])
        variants=[[],rows[::-1],rows[:1],rows+rows,[dict(rows[0],bytes=[True,18,19]),rows[1]],
                  [dict(rows[0],mipmaps=2),rows[1]],[dict(rows[0],width=True),rows[1]],
                  [dict(rows[0],bytes=[17,18]),rows[1]],[dict(rows[0],extra=1),rows[1]]]
        for bad in variants:
            with self.subTest(rows=bad),self.assertRaises(ValueError):p.candidate_actions([case],[],bad)
        actions,_=p.candidate_actions([case],[],rows)
        for bad_role in ('','normalized','alias-bmp','dispatch-unknown'):
            changed=copy.deepcopy(actions[:1]);changed[0]['role']=bad_role
            with self.subTest(role=bad_role),self.assertRaises(ValueError):p.candidate_program(changed)

    def test_disjoint_control_identity_and_consistent_shared_input_binding(self):
        case=tiny();rows=native_rows([case])
        with self.assertRaises(ValueError):
            p.candidate_actions([case],[dict(id=case['id'],bytes=[],error=0)],rows)
        actions,_=p.candidate_actions([case],[],rows)
        self.assertIn('input0',p.candidate_program(actions))
        for change in (dict(width=2),dict(bytes=case['bytes']+[0]),dict(extended=True)):
            bad=copy.deepcopy(actions);bad[1]['case']=dict(bad[1]['case'],**change)
            with self.subTest(change=change),self.assertRaises(ValueError):p.candidate_program(bad)

    def test_all_corpus_actions_and_compared_bytes_have_exhaustive_partitions(self):
        cases=p.fixtures();invalid=p.controls();actions,reference=p.candidate_actions(cases,invalid,native_rows(cases))
        plan=p.plan_partitions(actions)
        self.assertEqual(len(reference),len(cases))
        self.assertEqual(len(actions),6*len(cases)+4*sum(c['extended'] for c in cases)+2*len(invalid))
        self.assertEqual(sum(b['count'] for b in plan),len(actions))
        self.assertEqual(sum(b['compared_bytes'] for b in plan),sum(len(a['expected'].get('bytes',[])) for a in actions))
        self.assertTrue(all(1<=b['count']<=32 and 0<b['source_bytes']<=196608 for b in plan))
        flattened=[a for b in plan for a in actions[b['start']:b['start']+b['count']]]
        self.assertEqual(flattened,actions);self.assertEqual(p.action_digest(flattened),p.action_digest(actions))
        lanes=lanes_for(plan);p.finish_lanes(lanes,actions,plan)
        self.assertTrue(all(row['passed'] for row in lanes.values()))

    def test_process_group_success_nonzero_and_missing_group_cleanup_are_owned(self):
        for code,missing in ((0,False),(7,False),(0,True)):
            process=MagicMock(pid=123458,returncode=code)
            process.communicate.side_effect=[('complete','diagnostic'),('complete','diagnostic')]
            with patch.object(p.subprocess,'Popen',return_value=process) as launch, \
                 patch.object(p.os,'killpg',side_effect=ProcessLookupError() if missing else None) as kill:
                result=p.run_process_group(['tool'],cwd=Path('/tmp'),env={'ONLY':'child'},timeout=600)
            self.assertTrue(launch.call_args.kwargs['start_new_session'])
            kill.assert_called_once_with(process.pid,signal.SIGKILL)
            self.assertEqual(result.returncode,code);self.assertTrue(result.process_group_receipt['leader_reaped'])
            self.assertEqual(result.process_group_receipt['process_group_cleanup'],'already-exited' if missing else 'SIGKILL')
            self.assertLessEqual(process.communicate.call_args.kwargs['timeout'],p.PROCESS_CLEANUP_SECONDS)

class BmpReferencePinTests(unittest.TestCase):
    def test_source_hashes_and_semantic_ranges_fail_closed(self):
        self.assertEqual(set(p.SOURCE_RANGES),{'src/rtextures.c','src/external/stb_image.h'})
        self.assertEqual(set(p.SOURCE_SHA256),set(p.SOURCE_RANGES))
        for name,ranges in p.SOURCE_RANGES.items():
            self.assertRegex(p.SOURCE_SHA256[name],r'^[0-9a-f]{64}$')
            self.assertTrue(all(type(first) is int and type(last) is int and 1<=first<=last for first,last in ranges))
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);file=root/'source.c';data=b'first\nsecond\nthird\n'
            file.write_bytes(data);digest=hashlib.sha256(data).hexdigest()
            with patch.object(p,'SOURCE_RANGES',{'source.c':[(1,2),(3,3)]}), \
                 patch.object(p,'SOURCE_SHA256',{'source.c':digest}):
                receipt=p.validate_reference_sources(root)['source.c']
                self.assertEqual(receipt['sha256'],digest)
                self.assertEqual(receipt['ranges'],[
                    dict(first=1,last=2,sha256=hashlib.sha256(b'first\nsecond\n').hexdigest()),
                    dict(first=3,last=3,sha256=hashlib.sha256(b'third\n').hexdigest())])
                file.write_bytes(data+b'drift')
                with self.assertRaises(ValueError):p.validate_reference_sources(root)
                file.unlink()
                with self.assertRaises((OSError,ValueError)):p.validate_reference_sources(root)

    def test_provenance_tracks_harness_oracles_pins_environment_and_library(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);raylib=root/'raylib';bend=root/'bend'
            native=raylib/'src'/'oracle.c';native.parent.mkdir(parents=True);native.write_text('oracle')
            compiler=bend/'bend2'/'main.ts';compiler.parent.mkdir(parents=True);compiler.write_text('compiler')
            args=type('Args',(),dict(raylib_source=raylib,bend_source=bend))()
            with patch.object(p,'source_gate',return_value={'src/image.bend':'library-hash'}):
                receipt=p.tracked_sources(args)
            self.assertEqual(receipt['library'],{'src/image.bend':'library-hash'})
            paths=receipt['dependencies']
            for relative in ('tools/bmp_format_probe.py','tests/test_bmp_format_harness.py','tools/bmp_probe.py',
                             'tools/conformance.py','tools/reference_environment.py','toolchain.json','LAWS.bend','PROOF.bend'):
                self.assertEqual(paths[str(p.ROOT/relative)],p.digest(p.ROOT/relative))
            self.assertEqual(paths[str(native)],p.digest(native));self.assertEqual(paths[str(compiler)],p.digest(compiler))


class BmpMockedRunTests(unittest.TestCase):
    """Full orchestration with synthetic rows; no compiler or child is launched."""
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.work=Path(self.tmp.name);p.SEALED.clear()
        self.lock=json.loads((p.ROOT/'toolchain.json').read_text())
        self.case=tiny(3,extended=True);self.control=dict(id='unit-invalid',bytes=[],error=0)
        self.rows=native_rows([self.case]);self.actions,_=p.candidate_actions([self.case],[self.control],self.rows)
        self.plan=p.plan_partitions(self.actions);self.calls=[];self.pin_calls=[]
        self.tools={name:self.work/name for name in ('bun','clang','cmake')}
        for name,path in self.tools.items():path.write_text('fake '+name)
        self.archive=self.work/'libraylib.a';self.archive.write_bytes(b'fake archive')

    def tearDown(self):
        p.SEALED.clear();self.tmp.cleanup()

    def frame(self,actions):
        return ''.join(encoded(a,a['expected']['bytes']) if 'bytes' in a['expected'] else json.dumps(a['expected'])+'\n'
                       for a in actions)

    def run_mock(self,mode=None):
        target=self.work/'report';target.mkdir(exist_ok=True)
        (target/'results.json').write_text('{"passed":true,"stale":"must disappear"}')
        reference=''.join(encoded(a,row['bytes']) for a,row in zip(p.native_actions([self.case]),self.rows))
        qualified=json.dumps(dict(little_endian=True,bmp_enabled=True,effective_alpha_routing=True,formats=[4,7]))
        source_calls=[]
        def tracked(args):
            source_calls.append(1)
            return dict(library={},dependencies={},**({'drift':True} if mode=='sources' and len(source_calls)>1 else {}))
        def checkout(*args):
            self.pin_calls.append(args)
            if mode=='pins' and len(self.pin_calls)==3:raise ValueError('pinned source changed')
        def record(command,work,label,**kwargs):
            self.calls.append((label,list(map(str,command)),kwargs))
            if label=='bun-version':return 'wrong' if mode=='bun' else self.lock['bun']['version']
            if label=='clang-version':return 'test clang'
            if label=='qualification':return '{}' if mode=='qualification' else qualified
            if label=='reference':
                if mode=='reference-empty':return ''
                if mode=='reference-extra':return reference+reference
                if mode=='reference-reordered':return ''.join(encoded(a,row['bytes']) for a,row in reversed(list(zip(p.native_actions([self.case]),self.rows))))
                return reference
            if any(label.startswith(lane+'-') for lane in p.LANES):
                index=int(label.rsplit('-',1)[1]);part=self.plan[index]
                selected=self.actions[part['start']:part['start']+part['count']]
                result=self.frame(selected)
                if label.startswith('javascript-'):
                    if mode=='candidate-empty':return ''
                    if mode=='candidate-missing':return self.frame(selected[:-1])
                    if mode=='candidate-extra':return result+result
                    if mode=='candidate-order':return self.frame(list(reversed(selected)))
                    if mode=='candidate-bytes':return result.replace('[17, 17, 17]','[18, 17, 17]',1)
                    if mode=='sealed':(work/'candidate-0.bend').write_text('source changed')
                    if mode=='loader':os.environ['LD_LIBRARY_PATH']='changed'
                    if mode=='tool':self.tools['bun']=self.work/'replacement'
                return result
            return ''
        with ExitStack() as stack:
            stack.enter_context(patch.dict(os.environ,{},clear=False))
            stack.enter_context(patch.object(p,'fixtures',return_value=[self.case]))
            stack.enter_context(patch.object(p,'controls',return_value=[self.control]))
            stack.enter_context(patch.object(p,'checkout',side_effect=checkout))
            stack.enter_context(patch.object(p,'tracked_sources',side_effect=tracked))
            stack.enter_context(patch.object(p,'validate_reference_sources',return_value={'test':'pinned'}))
            stack.enter_context(patch.object(p,'native_archive',return_value=(self.archive,dict(mode='mock-only'))))
            stack.enter_context(patch.object(p.shutil,'which',side_effect=lambda name:str(self.tools[name])))
            stack.enter_context(patch.object(p.subprocess,'check_output',return_value='unit-revision\n'))
            stack.enter_context(patch.object(p,'record_run',side_effect=record))
            stack.enter_context(patch('sys.stdout',new_callable=io.StringIO))
            argv=['--bend-source',str(self.work/'bend'),'--raylib-source',str(self.work/'raylib'),'--build-dir',str(target)]
            if mode:
                with self.assertRaises(ValueError):p.main(argv)
            else:p.main(argv)
        return json.loads((target/'results.json').read_text())

    def test_success_requires_both_pin_passes_clean_native_environment_and_all_lanes(self):
        before=dict(os.environ);report=self.run_mock()
        self.assertTrue(report['passed']);self.assertNotIn('stale',report);self.assertEqual(dict(os.environ),before)
        self.assertEqual(self.pin_calls,[
            (self.work/'bend',self.lock['bend']['revision'],self.lock['bend']['patch']),
            (self.work/'raylib',self.lock['raylib']['revision']),
            (self.work/'bend',self.lock['bend']['revision'],self.lock['bend']['patch']),
            (self.work/'raylib',self.lock['raylib']['revision'])])
        self.assertEqual(report['observations_per_lane'],len(self.actions));self.assertEqual(report['native_rejections'],0)
        self.assertEqual((report['native_raw_bytes'],report['native_normalized_bytes']),(3,4))
        self.assertEqual(report['raw_compared_bytes_per_lane'],12)
        self.assertEqual(report['compared_bytes_per_lane'],sum(len(a['expected'].get('bytes',[])) for a in self.actions))
        self.assertTrue(all(row['passed'] for row in report['lanes'].values()))
        from reference_environment import LOADER_NAMES
        for label,command,kwargs in self.calls:
            if label in ('clang-version','qualification-compile','qualification','reference-compile','reference'):
                self.assertEqual(kwargs['receipt']['policy'],'clean-loader')
                self.assertTrue(all(name not in kwargs['environment'] for name in LOADER_NAMES))
            if label.startswith(('cpu-1-','cpu-2-')):self.assertIn('--gpu',command);self.assertIn('off',command)
        self.assertIn('candidate-0.bend',' '.join(report['sealed_artifacts']))

    def test_incorrect_bun_or_failed_qualification_never_reaches_candidate(self):
        for mode in ('bun','qualification'):
            with self.subTest(mode=mode):
                self.calls=[];self.pin_calls=[];report=self.run_mock(mode)
                self.assertFalse(report['passed']);self.assertNotIn('stale',report)
                self.assertFalse(any(label.startswith('compile-') for label,_,_ in self.calls))
                self.assertIn('failure',report)

    def test_incomplete_extra_reordered_reference_or_candidate_cannot_pass(self):
        for mode in ('reference-empty','reference-extra','reference-reordered','candidate-empty',
                     'candidate-missing','candidate-extra','candidate-order','candidate-bytes'):
            with self.subTest(mode=mode):
                self.calls=[];self.pin_calls=[];report=self.run_mock(mode)
                self.assertFalse(report['passed']);self.assertIn('failure',report)
                self.assertNotIn('stale',report)
                self.assertTrue(all(row['passed'] is False for row in report['lanes'].values()))

    def test_late_pin_source_loader_tool_or_sealed_source_drift_cannot_pass(self):
        for mode in ('pins','sources','loader','tool','sealed'):
            with self.subTest(mode=mode):
                self.calls=[];self.pin_calls=[]
                self.tools['bun']=self.work/'bun'
                report=self.run_mock(mode)
                self.assertFalse(report['passed']);self.assertIn('failure',report)
                self.assertNotIn('stale',report)


if __name__=='__main__':unittest.main()
