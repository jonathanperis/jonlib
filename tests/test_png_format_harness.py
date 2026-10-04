"""Independent, source-only PNG admission and fail-closed harness tests.

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
import png_format_probe as p
from png_probe import png, chunk, filtered, adam_filtered, fixtures as legacy_fixtures


def tiny(channels=3, extended=False):
    return dict(id='tiny', width=1, height=1, channels=channels,
                bytes=list(png(1,1,{1:0,2:4,3:2,4:6}[channels],bytes([17,18,19,20][:channels]))), extended=extended)


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
    return 'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY -DSUPPORT_FILEFORMAT_PNG\n'


def cache():
    return '\n'.join(k+':STRING='+v for k,v in dict(PLATFORM='Memory', CMAKE_BUILD_TYPE='Release',
        CUSTOMIZE_BUILD='ON', SUPPORT_FILEFORMAT_PNG='ON', SUPPORT_MODULE_RAUDIO='OFF',
        BUILD_EXAMPLES='OFF', USE_EXTERNAL_GLFW='OFF').items())+'\n'



class PngRunnerTests(unittest.TestCase):

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
        self.assertEqual(p.report_directories(['--build-di',str(a)]),[p.BUILD/'png-format-probe'])
        self.assertEqual(p.report_directories(['--','--build-dir',str(a)]),[p.BUILD/'png-format-probe'])

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

    def test_native_build_explicit_png_and_configuration_checked_before_execution(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();commands=[]
        def record(command,work,label,**kwargs):
            commands.append(list(map(str,command)))
            if label=='configure':
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(cache());(directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(flags().replace(' -DSUPPORT_FILEFORMAT_PNG',''))
        with self.assertRaises(ValueError):p.native_archive(args,self.work,record)
        self.assertEqual(len(commands),1);self.assertIn('-DSUPPORT_FILEFORMAT_PNG=ON',commands[0]);self.assertIn('-DCUSTOMIZE_BUILD=ON',commands[0])


class PngFailureEvidenceTests(unittest.TestCase):

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


class PngPartitionTests(unittest.TestCase):

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


class PngProcessGroupTests(unittest.TestCase):

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


class PngProtocolTests(unittest.TestCase):
    def setUp(self):
        self.case=tiny(); self.action=dict(case=self.case, role='raw'); self.row=p.meta(self.case, 'raw')

    def text(self, row=None, parts=None):
        return '\n'.join(json.dumps(v) for v in [self.row if row is None else row,
            *([[17,18,19], 'end'] if parts is None else parts)])+'\n'

    def test_complete_rgb_rgba_raw_roundtrip_alias_and_normalized(self):
        for channels in (1,2,3,4):
            case=tiny(channels)
            for role in ('raw','raw-roundtrip','factory','owner','alias-PNG','normalized','bridge','surface'):
                action=dict(case=case,role=role)
                count=channels if role in p.RAW_ROLES else 4
                values=list(range(17,17+count))
                row=p.parse_rows(encoded(action,values),[action])[0]
                self.assertEqual(row,dict(p.meta(case,role),bytes=values))
                self.assertEqual(row['format'],p.FORMATS[channels] if role in p.RAW_ROLES else 7)

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


class PngNativeAndOwnershipTests(unittest.TestCase):
    def test_native_raw_is_observed_before_normalization_and_alias_reload(self):
        for channels in (1,2,3,4):
            case=tiny(channels,extended=True);program=p.reference_program([case])
            self.assertLess(program.index('"raw",image)'),program.index('ImageFormat(&image,7)'))
            self.assertLess(program.index('ImageFormat(&image,7)'),program.index('"normalized",image)'))
            for suffix in ('.png','.PNG'):self.assertIn('LoadImageFromMemory("'+suffix+'"',program)
            for token in ('if(!little_endian())','image.mipmaps!=1',f'image.format!={p.FORMATS[channels]}',
                          f'GetPixelDataSize(image.width,image.height,image.format)!={channels}',
                          'GetPixelDataSize(image.width,image.height,image.format)!=4'):
                self.assertIn(token,program)
            self.assertEqual(program.count('Image image=LoadImageFromMemory'),1)
            self.assertEqual(program.count('image=LoadImageFromMemory'),2)
            self.assertNotIn('LoadImageColors',program);self.assertNotIn('stbi_load',program)
            self.assertEqual([a['role'] for a in p.native_actions([case])],['raw','normalized','alias-PNG'])

    def test_native_cache_and_actual_flags_both_required_and_unambiguous(self):
        self.assertEqual(p.validate_native_config(cache(),flags())['SUPPORT_FILEFORMAT_PNG'],'ON')
        commented='// Generated cache\n\n'+'\n// option\n'.join(cache().splitlines())+'\n'
        self.assertEqual(p.validate_native_config(commented,flags())['PLATFORM'],'Memory')
        with self.assertRaises(ValueError):p.validate_native_config(cache()+'PLATFORM:STRING=Memory\n',flags())
        for macro in ('SUPPORT_FILEFORMAT_PNG','EXTERNAL_CONFIG_FLAGS','PLATFORM_MEMORY'):
            self.assertEqual(p.validate_native_config(cache(),flags().replace('-D'+macro,'-D '+macro+'=1'))['PLATFORM'],'Memory')
            for broken in (flags().replace(' -D'+macro,''),flags()+' -D'+macro,flags()+' -U'+macro,
                           flags()+' -U '+macro,flags()+' -D '+macro+'=0',flags().replace('-D'+macro,'-D'+macro+'=0')):
                with self.subTest(macro=macro,flags=broken),self.assertRaises(ValueError):
                    p.validate_native_config(cache(),broken)
        for broken in (flags()+' -DPLATFORM_DESKTOP',flags()+' -D',flags()+' -U', '# '+flags()):
            with self.assertRaises(ValueError):p.validate_native_config(cache(),broken)
        for old,new in [('PNG:STRING=ON','PNG:STRING=OFF'),('CUSTOMIZE_BUILD:STRING=ON','CUSTOMIZE_BUILD:STRING=OFF'),
                        ('PLATFORM:STRING=Memory','PLATFORM:STRING=Desktop'),('CMAKE_BUILD_TYPE:STRING=Release','CMAKE_BUILD_TYPE:STRING=Debug')]:
            with self.assertRaises(ValueError):p.validate_native_config(cache().replace(old,new),flags())

    def test_native_qualification_requires_exact_typed_routing_proof(self):
        row=dict(p.QUALIFICATION)
        self.assertEqual(p.qualification(json.dumps(row)),row)
        for key,value in [('little_endian',False),('png_enabled',False),('structural_channels',1),
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
        for channels in (1,2,3,4):
            case=tiny(channels,extended=True);rows=native_rows([case])
            actions,_=p.candidate_actions([case],p.controls()[:1],rows);program=p.candidate_program(actions)
            for token in ('word <= 16777215','U32.is_eq(format, 7)','+format: U32','(pixels, +word)',
                          'J.Image.Formatted.decode_png','J.Image.Formatted.to_surface','J.Surface.to_formatted',
                          'J.Image.Formatted.from_bytes','J.Image.Formatted.get','J.Surface.decode_png',
                          'J.Surface.decode_image(','J.UncontractedDecode{}','J.FusedDecode{}',
                          'J.Image.Formatted.export(image)','owner.read(result, 0, 0, Some{first})',
                          'def roundtrip.bytes(values: List<U32>, bytes: +List<U32>) -> +List<U32>:',
                          'J.Image.Formatted.from_bytes(width, height, format, roundtrip.bytes(bytes, Nil{}))',
                          'roundtrip.exported(J.Image.Formatted.export(image))',
                          '(width - 1 : U32)','4294967295, 0, None{}','0, 4294967295, None{}',
                          'formatted.error(J.Image.Formatted.decode_png','surface.error(J.Surface.decode_png'):
                self.assertIn(token,program)
            self.assertIn(f'J.Image.Formatted.from_bytes(1, 1, {p.FORMATS[channels]},',program)
            self.assertNotIn('Image.Formatted.convert',program)
            roles=[a['role'] for a in actions]
            self.assertEqual(set(roles),{'raw','raw-roundtrip','bridge','surface','factory','owner',
                                         'dispatch-png','dispatch-PNG','uncontracted','fused','formatted-error','surface-error'})
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
        for bad_role in ('','normalized','alias-png','dispatch-unknown'):
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

class PngReferencePinTests(unittest.TestCase):
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
            for relative in ('tools/png_format_probe.py','tests/test_png_format_harness.py','tools/png_probe.py','tools/bmp_probe.py',
                             'tools/conformance.py','tools/reference_environment.py','toolchain.json','LAWS.bend','PROOF.bend'):
                self.assertEqual(paths[str(p.ROOT/relative)],p.digest(p.ROOT/relative))
            self.assertEqual(paths[str(native)],p.digest(native));self.assertEqual(paths[str(compiler)],p.digest(compiler))


class PngMockedRunTests(unittest.TestCase):
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
        qualified=json.dumps(p.QUALIFICATION)
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
            if label=='reference-0':
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
            if label in ('clang-version','qualification-compile','qualification','reference-0-compile','reference-0'):
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


class PngAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.cases=p.fixtures();cls.controls=p.controls();cls.by_id={c['id']:c for c in cls.cases}

    def test_all_193_legacy_inputs_31677_pixels_and_39_controls_are_byte_exact(self):
        accepted,rejected,extra=legacy_fixtures();self.assertEqual(extra,[])
        self.assertEqual((len(accepted),len(rejected)),(193,39))
        legacy=[c for c in self.cases if c['id'].startswith('legacy-')]
        self.assertEqual(sum(c['width']*c['height'] for c in legacy),31677)
        self.assertEqual([(c['id'][7:],c['bytes']) for c in legacy],[(c['id'],c['bytes']) for c in accepted])
        self.assertEqual([dict(c,id=c['id'][7:]) for c in self.controls if c['id'].startswith('legacy-')],rejected)
        self.assertTrue(all(not c['extended'] for c in legacy))

    def test_actual_bytes_determine_structural_channels_not_opacity(self):
        expected={'palette-trns-empty':4,'palette-trns-opaque':4,'palette-trns-unused-transparent':4,
                  'palette-trns-repeated':4,'palette-trns-plte-sticky-empty':4,
                  'palette-trns-plte-sticky-transparent':4,'palette-plte-trns-plte-trns':4,
                  'trns-no-match-0':2,'trns-no-match-2':4,'legacy-palette-opaque':3}
        for name,channels in expected.items():
            with self.subTest(name=name):self.assertEqual(p.inspect_header(self.by_id[name]['bytes'])['channels'],channels)
        self.assertEqual({p.FORMATS[c['channels']] for c in self.cases},{1,2,4,7})
        for channels in (1,2,3,4):
            self.assertEqual(p.inspect_header(tiny(channels)['bytes'])['channels'],channels)

    def test_dimensions_channels_depth_and_pass_counts_derive_from_actual_ihdr(self):
        for case in self.cases:
            header=p.inspect_header(case['bytes'])
            self.assertEqual([header[k] for k in ('width','height','channels')],[case[k] for k in ('width','height','channels')])
            self.assertEqual(sum(s['filtered_bytes'] for s in header['passes']),header['filtered_bytes'])
        self.assertEqual(len(p.inspect_header(self.by_id['legacy-adam7-0-1-1-1']['bytes'])['passes']),1)
        self.assertEqual(len(p.inspect_header(self.by_id['legacy-adam7-0-1-17-13']['bytes'])['passes']),7)

    def test_all_legacy_and_added_controls_are_excluded_from_native(self):
        for case in self.controls:
            with self.subTest(name=case['id']),self.assertRaises(ValueError):p.inspect_header(case['bytes'],fixture_budget=False)
        self.assertEqual([a['case']['id'] for a in p.native_actions(self.cases) if a['case']['id'] in {c['id'] for c in self.controls}],[])
        for case in self.controls[:10]:
            with self.assertRaises(ValueError):p.reference_program([dict(case,width=1,height=1,channels=4,extended=False)])

    def test_byte_domain_covers_crc_ignored_trailer_and_every_encoded_position(self):
        data=tiny()['bytes']+[0,1,2]
        for at in range(len(data)):
            for value in (True,-1,256,1.0):
                bad=data.copy();bad[at]=value
                with self.subTest(at=at,value=value),self.assertRaises(ValueError):p.inspect_header(bad)
        for data in (b'PNG',None,{},[False]):
            with self.assertRaises(ValueError):p.inspect_header(data)

    def test_checksum_and_absent_adler_native_semantics_are_preserved(self):
        import zlib
        raster=b'\0\x7f';stream=zlib.compress(raster)
        for value in (stream,stream[:-4],stream[:-4]+b'\xff'*4):
            self.assertEqual(p.bounded_inflate(value,False,len(raster)),raster)
        for name in ('legacy-ignored-checksums','legacy-absent-adler'):
            self.assertEqual(p.inspect_header(self.by_id[name]['bytes'])['channels'],4)
        data=tiny()['bytes'];data[-1]^=255
        self.assertEqual(p.inspect_header(data)['channels'],3)

    def test_standard_and_cgbi_framing_are_distinct_and_independently_bounded(self):
        import zlib
        raster=b'\0\x7f';framed=zlib.compress(raster);raw=framed[2:-4]
        self.assertEqual(p.bounded_inflate(raw,True,2),raster)
        for stream,cgbi,size in [(framed,True,2),(raw,False,2),(framed,False,1),(framed,False,3),
                                  (framed[:-5],False,2),(b'',False,2),(b'\x78\x00'+raw,False,2),
                                  (b'\x78\x20'+raw,False,2)]:
            with self.subTest(stream=stream,cgbi=cgbi,size=size),self.assertRaises(ValueError):p.bounded_inflate(stream,cgbi,size)
        # Admission asks an independent inflater for exactly expected+1 bytes.
        fake=MagicMock();fake.decompress.return_value=raster;fake.eof=True;fake.unconsumed_tail=b''
        with patch.object(zlib,'decompressobj',return_value=fake) as inflate:
            self.assertEqual(p.bounded_inflate(framed,False,2),raster)
        inflate.assert_called_once_with(-15);fake.decompress.assert_called_once_with(framed[2:],3)
        fake.flush.assert_not_called()

    def test_actual_palette_indices_are_reconstructed_after_every_filter(self):
        for depth in (1,2,4,8):
            for interlaced in (False,True):
                for mode in range(5):
                    for valid in (False,True):
                        data=png(9,9,3,bytes([1])*81,(mode,),depth=depth,interlaced=interlaced,palette=b'\1\2\3'+(b'\4\5\6' if valid else b''))
                        with self.subTest(depth=depth,adam=interlaced,mode=mode,valid=valid):
                            if valid:self.assertEqual(p.inspect_header(list(data))['maximum_index'],1)
                            else:
                                with self.assertRaisesRegex(ValueError,'palette index'):p.inspect_header(list(data))

    def test_unused_packed_padding_bits_do_not_become_indices(self):
        for depth in (1,2,4):
            data=png(1,1,3,b'\0',depth=depth,palette=b'\1\2\3')
            self.assertEqual(p.inspect_header(list(data))['maximum_index'],0)

    def test_pass_filter_rows_exact_lengths_and_empty_passes(self):
        import zlib
        for interlaced in (False,True):
            raster=adam_filtered(9,9,0,bytes(81),(0,),1) if interlaced else filtered(9,9,0,bytes(81),(0,),1)
            for bad in (raster[:-1],raster+b'\0',bytes([5])+raster[1:]):
                data=png(9,9,0,bytes(81),depth=1,interlaced=interlaced,stream=zlib.compress(bad))
                with self.assertRaises(ValueError):p.inspect_header(list(data))
        self.assertEqual(p.pass_layout(1,1,1,1,1),[dict(width=1,height=1,row_bytes=1,filtered_bytes=2)])

    def test_cgbi_markers_preserve_native_default_channels_and_framing(self):
        for case in self.cases:
            if 'cgbi' in case['id']:
                observed=p.inspect_header(case['bytes']);self.assertTrue(observed['cgbi'])
        observed=p.inspect_header(self.by_id['legacy-cgbi-after-idat']['bytes'])
        self.assertGreater(observed['chunks'].index('CgBI'),observed['chunks'].index('IDAT'))
        self.assertEqual(self.by_id['cgbi-default-bgr-premultiplied']['channels'],4)
        self.assertIn('cgbi-default',p.QUALIFY);self.assertIn('p[0]!=3||p[1]!=8||p[2]!=12||p[3]!=16',p.QUALIFY)

    def test_palette_chunk_and_transparency_structures_fail_closed(self):
        for extra in ([(b'PLTE',b'')],[(b'PLTE',b'\0')],[(b'PLTE',bytes(771))],[(b'ABCD',b'')]):
            with self.assertRaises(ValueError):p.inspect_header(list(png(1,1,0,b'\0',extra=extra)))
        for color,alpha in ((0,b''),(0,b'\0'),(2,b'\0'*5),(4,b'\0'*2),(6,b'\0'*6)):
            with self.assertRaises(ValueError):p.inspect_header(list(png(1,1,color,bytes(p.CHANNELS[color]),transparency=alpha)))
        data=png(1,1,3,b'\0',palette=b'\1\2\3')
        with self.assertRaises(ValueError):p.inspect_header(list(data[:-12]+chunk(b'PLTE',b'\4\5\6')+data[-12:]))
        with self.assertRaises(ValueError):p.inspect_header(list(data[:-12]+chunk(b'tRNS',b'')+data[-12:]))

    def test_signature_header_chunk_overflow_and_missing_terminator_fail_closed(self):
        data=tiny()['bytes']
        malformed=[data[:8]+data[33:],data[:33]+data[8:],list(p.SIGNATURE+chunk(b'tEXt',b'x'))+data[8:],
                   list(p.SIGNATURE+b'\xff\xff\xff\xffIHDR'),data[:-12],data[:-12]+list(chunk(b'IEND',b'x'))]
        for bad in malformed:
            with self.assertRaises(ValueError):p.inspect_header(bad)
        for at in range(8):
            bad=data.copy();bad[at]^=1
            with self.assertRaises(ValueError):p.inspect_header(bad)

    def test_actual_nonpng_content_never_reaches_shared_stb_suffix_loader(self):
        for case in self.controls:
            if case['id'].startswith('non-png-'):
                with self.assertRaises(ValueError):p.inspect_header(case['bytes'])
        self.assertIn('shares',p.__doc__);self.assertIn('stb',p.__doc__)
        self.assertNotIn('non-png-',p.reference_program(self.cases))

    def test_native_declared_metadata_ids_and_fixture_budgets_are_checked(self):
        case=tiny()
        for key,value in [('id','bad/id'),('id',3),('width',True),('height',1.0),('channels',4),('extended',1),('extra',0)]:
            with self.subTest(key=key),self.assertRaises(ValueError):p.validate_cases([dict(case,**{key:value})])
        for cases in ([],None,[case,case]):
            with self.assertRaises(ValueError):p.validate_cases(cases)
        with patch.object(p,'MAX_TOTAL_BYTES',1),self.assertRaises(ValueError):p.validate_cases([case])
        data=list(png(100,100,0,bytes(10000)))
        with self.assertRaises(ValueError):p.inspect_header(data)
        self.assertEqual(p.inspect_header(data,fixture_budget=False)['width'],100)
        with self.assertRaisesRegex(ValueError,'mislabeled'):p.validate_controls([dict(id='valid-budget',bytes=data,error=2)])

    def test_control_schema_and_valid_api_input_mislabeled_fail(self):
        for control in [dict(id='valid',bytes=tiny()['bytes'],error=0),dict(id='bool',bytes=[],error=True),
                        dict(id='uint',bytes=[-1],error=1),dict(id='bool-byte',bytes=[True],error=1),
                        dict(id='wide',bytes=[4294967296],error=1),dict(id='extra',bytes=[],error=0,extra=1)]:
            with self.assertRaises(ValueError):p.validate_controls([control])
        with self.assertRaises(ValueError):p.validate_controls([self.controls[0],self.controls[0]])

    def test_exact_encoded_cap_and_first_error_precedence_have_compact_runtime_inputs(self):
        cap=self.by_id['encoded-exact-cap'];self.assertEqual(len(cap['bytes']),1048576)
        self.assertEqual(p.inspect_header(cap['bytes'])['width'],1)
        by_id={c['id']:c for c in self.controls}
        expected={'encoded-cap-plus-one':2,'invalid-byte-at-cap-plus-one':1,'size-before-later-invalid-byte':2,'invalid-byte-before-cap':1}
        for name,error in expected.items():
            case=by_id[name];self.assertEqual(case['error'],error)
            self.assertGreater(len(case['bytes']),1048576)
            self.assertLess(len(p.input_expression(case['bytes'])),1000)
        self.assertLess(len(p.input_expression(cap['bytes'])),1000)
        source=p.reference_program([cap]);self.assertIn('malloc(1048576)',source);self.assertIn('memset(data+',source);self.assertIn('free(data);',source)
        self.assertLess(len(source),10000)
        self.assertEqual(by_id['invalid-byte-at-cap-plus-one']['bytes'][1048576],256)
        self.assertEqual(by_id['size-before-later-invalid-byte']['bytes'][1048576:],[0,256])

    def test_compact_input_is_lossless_for_arbitrary_runs_and_nonbyte_controls(self):
        for data in ([],[1],[1]*255,[2]*256,[3]*1000+[256],[1,2]+[0]*1048576+[256],list(range(256))*2):
            restored=[]
            for kind,values in p.compact_segments(data):restored.extend(values if kind=='literal' else [values[0]]*values[1])
            self.assertEqual(restored,data)
        self.assertIn('repeat_input(',p.BEND_PREFIX)
        self.assertIn('U32.is_eq(format, 1) && (word <= 255',p.BEND_PREFIX)
        self.assertIn('U32.is_eq(format, 2) && (word <= 65535',p.BEND_PREFIX)

    def test_filtered_64mib_boundary_controls_reach_size_or_stream_without_allocation(self):
        boundaries=[c for c in self.controls if c['id'].startswith('filtered-boundary-')]
        self.assertEqual(len(boundaries),8)
        for case in boundaries:
            w,h,depth,color,_,_,interlace=struct.unpack('>IIBBBBB',bytes(case['bytes'][16:29]))
            length=sum(s['filtered_bytes'] for s in p.pass_layout(w,h,p.CHANNELS[color],depth,interlace))
            self.assertEqual(case['error'],2 if length>67108864 else 4)
            self.assertLess(len(case['bytes']),100)
        self.assertEqual(sum(s['filtered_bytes'] for s in p.pass_layout(4095,4096,4,8,0)),67096576)
        self.assertEqual(sum(s['filtered_bytes'] for s in p.pass_layout(4096,4096,4,8,0)),67112960)


class PngNativePartitionTests(unittest.TestCase):
    def cases(self,count=35):return [dict(tiny(1+i%4,extended=bool(i%2)),id='partition-'+str(i)) for i in range(count)]
    def batches(self,plan):return [dict(entry,bytes=entry['compared_bytes'],passed=True,output_sha256='a'*64) for entry in plan]

    def test_native_partitions_bound_observations_and_exact_source_bytes(self):
        cases=self.cases();plan=p.plan_native_partitions(cases)
        self.assertEqual(sum(b['count'] for b in plan),len(cases))
        self.assertEqual(sum(b['observations'] for b in plan),len(p.native_actions(cases)))
        self.assertTrue(all(0<b['observations']<=32 and 0<b['source_bytes']<=196608 for b in plan))
        p.validate_native_partitions(cases,plan);p.finish_native(cases,plan,self.batches(plan))
        self.assertEqual(plan,p.plan_native_partitions(cases))

    def test_native_missing_extra_duplicate_reorder_schema_types_and_hashes_fail(self):
        cases=self.cases();plan=p.plan_native_partitions(cases)
        variants=[[],plan[:-1],plan+plan,plan[::-1]]
        for key,value in [('start',True),('count',0),('count',True),('observations',33),('source_bytes',196609),
                          ('source_sha256','0'*64),('cases_sha256','0'*64),('compared_bytes',True),('extra',1)]:
            bad=copy.deepcopy(plan);bad[0][key]=value;variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):p.validate_native_partitions(cases,bad)
        for cases in ([],None):
            with self.assertRaises(ValueError):p.plan_native_partitions(cases)
        with patch.object(p,'reference_program',return_value='x'*196609),self.assertRaises(ValueError):p.plan_native_partitions(self.cases(1))

    def test_native_complete_receipts_have_strict_types_hashes_and_full_bytes(self):
        cases=self.cases();plan=p.plan_native_partitions(cases);batches=self.batches(plan)
        for bad in ([],batches[:-1],batches+batches,batches[::-1]):
            with self.assertRaises(ValueError):p.finish_native(cases,plan,bad)
        for key,value in [('bytes',True),('bytes',0),('passed',1),('output_sha256',''),('extra',1),('start',True)]:
            bad=copy.deepcopy(batches);bad[0][key]=value
            with self.assertRaises(ValueError):p.finish_native(cases,plan,bad)


if __name__=='__main__':unittest.main()
