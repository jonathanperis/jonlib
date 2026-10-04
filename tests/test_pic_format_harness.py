"""Independent, source-only PIC admission and fail-closed harness tests.

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
import pic_format_probe as p
from pic_probe import pic, pic_packets, pic_header, fixtures as legacy_fixtures


def tiny(channels=3, extended=False):
    return dict(id='tiny', width=1, height=1, channels=channels,
                bytes=pic(1,1,[(0xe0 if channels==3 else 0xf0,[0x11121314])]), extended=extended)


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
    return 'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY -DSUPPORT_FILEFORMAT_PIC\n'


def cache():
    return '\n'.join(k+':STRING='+v for k,v in dict(PLATFORM='Memory', CMAKE_BUILD_TYPE='Release',
        CUSTOMIZE_BUILD='ON', SUPPORT_FILEFORMAT_PIC='ON', SUPPORT_MODULE_RAUDIO='OFF',
        BUILD_EXAMPLES='OFF', USE_EXTERNAL_GLFW='OFF').items())+'\n'



class PicRunnerTests(unittest.TestCase):

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
        self.assertEqual(p.report_directories(['--build-di',str(a)]),[p.BUILD/'pic-format-probe'])
        self.assertEqual(p.report_directories(['--','--build-dir',str(a)]),[p.BUILD/'pic-format-probe'])

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

    def test_native_build_explicit_pic_and_configuration_checked_before_execution(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();commands=[]
        def record(command,work,label,**kwargs):
            commands.append(list(map(str,command)))
            if label=='configure':
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(cache());(directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(flags().replace(' -DSUPPORT_FILEFORMAT_PIC',''))
        with self.assertRaises(ValueError):p.native_archive(args,self.work,record)
        self.assertEqual(len(commands),1);self.assertIn('-DSUPPORT_FILEFORMAT_PIC=ON',commands[0]);self.assertIn('-DCUSTOMIZE_BUILD=ON',commands[0])


class PicFailureEvidenceTests(unittest.TestCase):

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


class PicPartitionTests(unittest.TestCase):

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


class PicProcessGroupTests(unittest.TestCase):

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


class PicProtocolTests(unittest.TestCase):
    def setUp(self):
        self.case=tiny(); self.action=dict(case=self.case, role='raw'); self.row=p.meta(self.case, 'raw')

    def text(self, row=None, parts=None):
        return '\n'.join(json.dumps(v) for v in [self.row if row is None else row,
            *([[17,18,19], 'end'] if parts is None else parts)])+'\n'

    def test_complete_rgb_rgba_raw_roundtrip_alias_and_normalized(self):
        for channels in (3,4):
            case=tiny(channels)
            for role in ('raw','raw-roundtrip','factory','owner','alias-PIC','normalized','bridge','surface'):
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


class PicNativeAndOwnershipTests(unittest.TestCase):
    def test_native_raw_is_observed_before_normalization_and_alias_reload(self):
        for channels in (3,4):
            case=tiny(channels,extended=True);program=p.reference_program([case])
            self.assertLess(program.index('"raw",image)'),program.index('ImageFormat(&image,7)'))
            self.assertLess(program.index('ImageFormat(&image,7)'),program.index('"normalized",image)'))
            for suffix in ('.pic','.PIC'):self.assertIn('LoadImageFromMemory("'+suffix+'"',program)
            for token in ('if(!little_endian())','image.mipmaps!=1',f'image.format!={p.FORMATS[channels]}',
                          f'GetPixelDataSize(image.width,image.height,image.format)!={channels}',
                          'GetPixelDataSize(image.width,image.height,image.format)!=4'):
                self.assertIn(token,program)
            self.assertEqual(program.count('Image image=LoadImageFromMemory'),1)
            self.assertEqual(program.count('image=LoadImageFromMemory'),2)
            self.assertNotIn('LoadImageColors',program);self.assertNotIn('stbi_load',program)
            self.assertEqual([a['role'] for a in p.native_actions([case])],['raw','normalized','alias-PIC'])

    def test_native_cache_and_actual_flags_both_required_and_unambiguous(self):
        self.assertEqual(p.validate_native_config(cache(),flags())['SUPPORT_FILEFORMAT_PIC'],'ON')
        commented='// Generated cache\n\n'+'\n// option\n'.join(cache().splitlines())+'\n'
        self.assertEqual(p.validate_native_config(commented,flags())['PLATFORM'],'Memory')
        with self.assertRaises(ValueError):p.validate_native_config(cache()+'PLATFORM:STRING=Memory\n',flags())
        for macro in ('SUPPORT_FILEFORMAT_PIC','EXTERNAL_CONFIG_FLAGS','PLATFORM_MEMORY'):
            self.assertEqual(p.validate_native_config(cache(),flags().replace('-D'+macro,'-D '+macro+'=1'))['PLATFORM'],'Memory')
            for broken in (flags().replace(' -D'+macro,''),flags()+' -D'+macro,flags()+' -U'+macro,
                           flags()+' -U '+macro,flags()+' -D '+macro+'=0',flags().replace('-D'+macro,'-D'+macro+'=0')):
                with self.subTest(macro=macro,flags=broken),self.assertRaises(ValueError):
                    p.validate_native_config(cache(),broken)
        for broken in (flags()+' -DPLATFORM_DESKTOP',flags()+' -D',flags()+' -U', '# '+flags()):
            with self.assertRaises(ValueError):p.validate_native_config(cache(),broken)
        for old,new in [('PIC:STRING=ON','PIC:STRING=OFF'),('CUSTOMIZE_BUILD:STRING=ON','CUSTOMIZE_BUILD:STRING=OFF'),
                        ('PLATFORM:STRING=Memory','PLATFORM:STRING=Desktop'),('CMAKE_BUILD_TYPE:STRING=Release','CMAKE_BUILD_TYPE:STRING=Debug')]:
            with self.assertRaises(ValueError):p.validate_native_config(cache().replace(old,new),flags())

    def test_native_qualification_requires_exact_typed_routing_proof(self):
        row=dict(p.QUALIFICATION)
        self.assertEqual(p.qualification(json.dumps(row)),row)
        for key,value in [('little_endian',False),('pic_enabled',False),('all_descriptor_channels',1),
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
                          'J.Image.Formatted.decode_pic','J.Image.Formatted.to_surface','J.Surface.to_formatted',
                          'J.Image.Formatted.from_bytes','J.Image.Formatted.get','J.Surface.decode_pic',
                          'J.Surface.decode_image(','J.UncontractedDecode{}','J.FusedDecode{}',
                          'J.Image.Formatted.export(image)','owner.read(result, 0, 0, Some{first})',
                          'def roundtrip.bytes(values: List<U32>, bytes: +List<U32>) -> +List<U32>:',
                          'J.Image.Formatted.from_bytes(width, height, format, roundtrip.bytes(bytes, Nil{}))',
                          'roundtrip.exported(J.Image.Formatted.export(image))',
                          '(width - 1 : U32)','4294967295, 0, None{}','0, 4294967295, None{}',
                          'formatted.error(J.Image.Formatted.decode_pic','surface.error(J.Surface.decode_pic'):
                self.assertIn(token,program)
            self.assertIn(f'J.Image.Formatted.from_bytes(1, 1, {p.FORMATS[channels]},',program)
            self.assertNotIn('Image.Formatted.convert',program)
            roles=[a['role'] for a in actions]
            self.assertEqual(set(roles),{'raw','raw-roundtrip','bridge','surface','factory','owner',
                                         'dispatch-pic','dispatch-PIC','uncontracted','fused','formatted-error','surface-error'})
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
        for bad_role in ('','normalized','alias-pic','dispatch-unknown'):
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

class PicReferencePinTests(unittest.TestCase):
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
            for relative in ('tools/pic_format_probe.py','tools/pic_format_audit.py','tests/test_pic_format_harness.py','tools/pic_probe.py','tools/bmp_probe.py',
                             'tools/conformance.py','tools/reference_environment.py','toolchain.json','LAWS.bend','PROOF.bend'):
                self.assertEqual(paths[str(p.ROOT/relative)],p.digest(p.ROOT/relative))
            self.assertEqual(paths[str(native)],p.digest(native));self.assertEqual(paths[str(compiler)],p.digest(compiler))


class PicMockedRunTests(unittest.TestCase):
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


class PicNativePartitionTests(unittest.TestCase):
    def test_explicit_action_inventories_are_exact_exhaustive_ordered_and_typed(self):
        case=tiny(4,True);actions,_=p.candidate_actions([case],[dict(id='bad',bytes=[],error=0)],native_rows([case]))
        for actual in (actions,p.native_actions([case])):
            expected=p.inventory(actual);p.validate_inventory(expected,actual)
            for bad in ([],expected[:-1],expected+expected,expected[::-1],expected+[expected[0]]):
                with self.assertRaises(ValueError):p.validate_inventory(bad,actual)
            for value in ({'id':True,'role':'raw'},{'id':'tiny','role':'raw','extra':1}):
                bad=copy.deepcopy(expected);bad[0]=value
                with self.assertRaises(ValueError):p.validate_inventory(bad,actual)

    def cases(self,count=35):return [dict(tiny(3+i%2,extended=bool(i%2)),id='partition-'+str(i)) for i in range(count)]
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



class PicAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases=p.fixtures();cls.controls=p.controls();cls.by_id={c['id']:c for c in cls.cases}

    def test_all_33_legacy_8867_pixels_and_24_controls_remain_byte_exact(self):
        accepted,invalid,_=legacy_fixtures()
        actual=[c for c in self.cases if c['id'].startswith('legacy-')]
        controls=[c for c in self.controls if c['id'].startswith('legacy-')]
        self.assertEqual(len(actual),33);self.assertEqual(sum(c['width']*c['height'] for c in actual),8867)
        self.assertEqual([(c['id'][7:],c['bytes']) for c in actual],[(c['id'],c['bytes']) for c in accepted])
        self.assertEqual(controls,[dict(c,id='legacy-'+c['id']) for c in invalid]);self.assertEqual(len(controls),24)

    def test_added_axes_and_alpha_coverage_are_meaningful_actual_inputs(self):
        for channels in (3,4):
            for axis,shape in [('row',(4096,1)),('column',(1,4096))]:
                c=self.by_id[f'c{channels}-axis-{axis}'];h=p.inspect_header(c['bytes'])
                self.assertEqual((h['width'],h['height'],h['channels']),(*shape,channels))
                self.assertGreater(len(set(c['bytes'][h['payload_offset']:])),200)
        ramp=self.by_id['alpha-ramp'];h=p.inspect_header(ramp['bytes'])
        self.assertEqual(ramp['bytes'][h['payload_offset']+3::4],list(range(256)))
        for name,value in [('all-opaque',255),('all-zero-alpha',0)]:
            c=self.by_id[name];h=p.inspect_header(c['bytes'])
            self.assertEqual(h['channels'],4);self.assertEqual(set(c['bytes'][h['payload_offset']+3::4]),{value})
        for name in ('early-alpha-followed-rgb','middle-alpha-followed-rgb','opaque-alpha-followed-rgb',
                     'overlap-alpha-zero','alpha-overwrites-final-opaque','alpha-then-empty-mask','ten-packets-alpha-first'):
            self.assertEqual(p.inspect_header(self.by_id[name]['bytes'])['channels'],4)
        overwritten=self.by_id['alpha-overwrites-final-opaque'];header=p.inspect_header(overwritten['bytes'])
        self.assertGreaterEqual(sum(bool(d['mask']&16) for d in header['descriptors']),3)
        self.assertFalse(header['descriptors'][-1]['mask']&16)
        row_bytes=overwritten['width']*sum(d['channels'] for d in header['descriptors'])
        for y in range(overwritten['height']):
            at=header['payload_offset']+y*row_bytes+overwritten['width']*5
            self.assertEqual(overwritten['bytes'][at:at+overwritten['width']],[255]*overwritten['width'])
        for kind in (1,2):
            for mask in range(0,256,16):
                c=self.by_id[f'all-masks-rle-{kind}-{mask:02x}'];h=p.inspect_header(c['bytes'])
                self.assertEqual(h['descriptors'],[dict(kind=kind,mask=mask,channels=(mask>>4).bit_count())])
                self.assertGreater(h['controls'],0);self.assertGreater(h['zero_counts'],0)
            self.assertEqual(p.inspect_header(self.by_id[f'rle-lowbits-{kind}']['bytes'])['channels'],4)
        for name in ('mixed-extended-255-256','mixed-raw128-repeat128-one','mixed-raw-pure-alpha-order'):
            self.assertGreater(p.inspect_header(self.by_id[name]['bytes'])['controls'],1)

    def test_all_descriptors_or_mask_not_opacity_or_last_descriptor_controls_layout(self):
        for mask in range(256):
            h=p.inspect_header(pic(1,1,[(mask,[0xffffffff])]))
            self.assertEqual(h['channels'],4 if mask&16 else 3)
            self.assertEqual(h['effective_mask'],mask)
        for masks in ((0x10,0xe0),(0xe0,0x10,0xe0),(0x10,0),(0x10,15),(0,0,0)):
            for color in (0,0xffffffff):
                h=p.inspect_header(pic(1,1,[(mask,[color]) for mask in masks]))
                self.assertEqual(h['channels'],4 if any(mask&16 for mask in masks) else 3)

    def test_every_global_byte_including_ignored_header_and_trailer_is_strict(self):
        base=pic(1,1,[(0xe0,[0])])+[0,255]
        for index in range(len(base)):
            for value in (True,0.0,-1,256):
                bad=base.copy();bad[index]=value
                with self.subTest(index=index,value=value),self.assertRaises(ValueError):p.inspect_header(bad)
        for data in (bytes(base),tuple(base),None):
            with self.assertRaises(ValueError):p.inspect_header(data)

    def test_ignored_header_lowbits_and_trailers_do_not_change_structural_metadata(self):
        base=pic(1,1,[(0xef,[0x12345678])]);original=p.inspect_header(base)
        for value in (0,255):
            data=base.copy();data[4:88]=[value]*84;data[96:104]=[value]*8
            self.assertEqual(p.inspect_header(data),original)
        observed=p.inspect_header(base+[1,2,3,4]);self.assertEqual(observed['tail_bytes'],4)
        self.assertEqual(observed['channels'],3)

    def test_descriptor_limit_nonzero_chains_and_postdescriptor_eof_are_exact(self):
        base=pic(1,1,[(0x80,[0])]*10)
        for at in range(104,140,4):base[at]=255
        self.assertEqual(p.inspect_header(base)['packet_count'],10)
        with self.assertRaises(ValueError):p.inspect_header(pic(1,1,[(0x80,[0])]*11))
        for length in range(104,109):
            with self.assertRaises(ValueError):p.inspect_header(pic(1,1,[(0,[0])])[:length])
        self.assertEqual(p.inspect_header(pic(1,1,[(0,[0])]))['payload_bytes'],0)

    def test_native_admission_never_accepts_any_malformed_control(self):
        for c in self.controls:
            with self.subTest(control=c['id']),self.assertRaises(ValueError):p.inspect_header(c['bytes'])
            self.assertEqual(p.checked_error(c['bytes']),c['error'])
            fake=dict(id=c['id'],bytes=c['bytes'],width=1,height=1,channels=3,extended=False)
            with self.assertRaises(ValueError):p.reference_program([fake])
        program=p.reference_program(self.cases[:2])
        self.assertNotIn('formatted-error',program);self.assertNotIn('surface-error',program)

    def test_native_safety_scan_runs_before_any_archive_or_decoder(self):
        with tempfile.TemporaryDirectory() as directory:
            args=['--bend-source',directory,'--raylib-source',directory,'--build-dir',directory+'/result']
            bad=dict(tiny(),bytes=[])
            with patch.object(p,'fixtures',return_value=[bad]),patch.object(p,'controls',return_value=[]), \
                 patch.object(p,'checkout'),patch.object(p,'native_archive') as native, \
                 patch.object(p,'record_run') as run,self.assertRaises(ValueError):p.main(args)
            native.assert_not_called();run.assert_not_called()

    def test_header_size_descriptor_and_stream_error_precedence_matches_surface(self):
        controls={c['id']:c for c in self.controls}
        for name,error in [('header-before-axis-0',0),('late-descriptor-before-stream',0),
                           ('axis-92-0',2),('literal-overrun-before-sample',4),
                           ('byte-before-literal-overrun-before-sample',1)]:
            self.assertEqual(p.checked_error(controls[name]['bytes']),error)
        actions,_=p.candidate_actions([tiny()],self.controls,native_rows([tiny()]))
        errors=[a for a in actions if a['role'].endswith('-error')]
        self.assertEqual(len(errors),2*len(self.controls))
        for first,second in zip(errors[::2],errors[1::2]):
            self.assertEqual((first['role'],second['role']),('formatted-error','surface-error'))
            self.assertEqual(first['expected']['error'],second['expected']['error'])

    def test_pure_zero_runs_clip_but_mixed_overruns_fail_before_samples(self):
        h=p.inspect_header(pic_packets(1,1,[(1,0xf0,[[0,0,0,0,0,255,1,2,3,4]])]))
        self.assertEqual((h['zero_counts'],h['clipped_counts']),(1,1))
        for payload in ([1,0],[129,0],[128,0,2]):
            self.assertEqual(p.checked_error(pic_packets(1,1,[(2,0xf0,[payload])])),4)
        for kind,payload in [(1,[0]*30),(2,[128,0,0]*30)]:
            self.assertEqual(p.checked_error(pic_packets(1,1,[(kind,0,[payload])])),3)

    def test_empty_masks_still_require_native_postcontrol_bytes(self):
        for kind in (1,2):
            data=pic_packets(1,1,[(kind,0,[[1 if kind==1 else 0]])])
            self.assertEqual(p.checked_error(data),3)
            self.assertIsNone(p.checked_error(data+[0]))
            self.assertEqual(p.inspect_header(data+[0])['channels'],3)
        self.assertIsNone(p.checked_error(pic_packets(1,1,[(2,0,[[128,0,1]])])))

    def test_dimensions_budget_and_encoded_policy_are_separate(self):
        self.assertEqual(len(self.by_id['encoded-over-one-mib']['bytes']),1048577)
        self.assertIsNone(p.checked_error(self.by_id['encoded-over-one-mib']['bytes']))
        data=pic(4096,4096,[(0,[])])
        self.assertIsNone(p.checked_error(data))
        with self.assertRaises(ValueError):p.inspect_header(data)
        for offset in (92,94):
            for value in (0,4097,65535):
                bad=tiny()['bytes'];bad[offset:offset+2]=[value>>8,value&255]
                self.assertEqual(p.checked_error(bad),2)

    def test_native_case_and_control_schema_types_identity_and_exact_error(self):
        for key,value in [('id','bad/name'),('id',1),('width',True),('height',1.0),('channels',4),('extended',1),('extra',0)]:
            with self.subTest(key=key),self.assertRaises(ValueError):p.validate_cases([dict(tiny(),**{key:value})])
        for cases in ([],None,[tiny(),tiny()]):
            with self.assertRaises(ValueError):p.validate_cases(cases)
        for key,value in [('error',True),('error',1.0),('error',99),('error',1),('bytes',[True]),('bytes',[-1]),('bytes',[4294967296]),('extra',0),('id','bad/name')]:
            with self.subTest(key=key),self.assertRaises(ValueError):p.validate_controls([dict(id='bad',bytes=[],error=0,**{})|{key:value}])
        with self.assertRaises(ValueError):p.validate_controls([dict(id='valid',bytes=tiny()['bytes'],error=0)])
        with patch.object(p,'MAX_TOTAL_BYTES',100),self.assertRaises(ValueError):p.validate_cases([tiny()])

    def test_nonpic_content_never_reaches_shared_stb_sniffer(self):
        for c in self.controls:
            if c['id'].startswith('non-pic-'):
                self.assertEqual(p.checked_error(c['bytes']),0)
        self.assertEqual(sum(c['id'].startswith('non-pic-') for c in self.controls),6)

    def test_compact_input_generation_preserves_every_encoded_value(self):
        cases=[[],[1,2,3],[1]*256,[1]*255+[2]*256+[3,4],[256]*256,[4294967295]*1024]
        for values in cases:
            expanded=[]
            for kind,part in p.compact_segments(values):expanded.extend(part if kind=='literal' else [part[0]]*part[1])
            self.assertEqual(expanded,values)
        c=self.by_id['encoded-over-one-mib']
        self.assertLess(len(p.input_expression(c['bytes'])),2000)
        self.assertLess(len(p.reference_program([c]).encode()),196608)



class PicIndependentAuditTests(unittest.TestCase):
    """Synthetic-only complete receipts: no compiler/native process is run."""
    def setUp(self):
        import pic_format_audit as audit
        self.a=audit;self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.work=self.root/'evidence'/('run-'+'0'*32);self.work.mkdir(parents=True)
        self.report_path=self.work.parent/'results.json';self.seals={};self.stack=ExitStack()
        self.case=tiny(3,True);self.control=dict(id='invalid',bytes=[],error=0)
        self.lock=json.loads((p.ROOT/'toolchain.json').read_text())
        self.bend=self.root/'bend';self.raylib=self.root/'raylib'
        for root,revision in [(self.root,'e'*40),(self.bend,self.lock['bend']['revision']),(self.raylib,self.lock['raylib']['revision'])]:
            self.put(root/'.git/HEAD',revision,seal=False)
        for relative in ('jonlib.bend','jonmath.bend','src/image.bend','tools/pic_format_probe.py','tools/pic_format_audit.py',
                         'tests/test_pic_format_harness.py','tools/pic_probe.py','tools/bmp_probe.py','tools/byte_probe.py',
                         'tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','LAWS.bend','PROOF.bend'):
            self.put(self.root/relative,'synthetic source\n')
        self.put(self.bend/'bend2/main.ts','synthetic compiler source\n')
        self.put(self.raylib/'src/oracle.c','synthetic oracle\n')
        for relative in self.lock['bend']['patch']['files']:
            self.put(self.bend/relative,'synthetic overlay\n',seal=False)
            self.lock['bend']['patch']['files'][relative]=audit.sha((self.bend/relative).read_bytes())
        overlay=self.root/self.lock['bend']['patch']['path'];self.put(overlay,'synthetic patch\n',seal=False)
        self.lock['bend']['patch']['sha256']=audit.sha(overlay.read_bytes())
        self.put(self.root/'toolchain.json',json.dumps(self.lock))
        self.stack.enter_context(patch.object(p,'ROOT',self.root))
        self.stack.enter_context(patch.object(p,'fixtures',return_value=[self.case]))
        self.stack.enter_context(patch.object(p,'controls',return_value=[self.control]))
        self.stack.enter_context(patch.object(p,'SOURCE_RANGES',{'src/oracle.c':[(1,1)]}))
        self.stack.enter_context(patch.object(p,'SOURCE_SHA256',{'src/oracle.c':audit.sha((self.raylib/'src/oracle.c').read_bytes())}))
        self.env=p.ReferenceEnvironment('clean-loader').receipt()
        self.tools={name:self.root/name for name in ('bun','clang','cmake')}
        for name,path in self.tools.items():self.put(path,'synthetic executable '+name)
        self.compiler=self.tools['clang'];self.archive=self.work/'raylib-build/raylib/libraylib.a'
        self.put(self.archive,'synthetic archive')
        self.cache=self.work/'raylib-build/CMakeCache.txt';self.flags=self.work/'raylib-build/raylib/CMakeFiles/raylib.dir/flags.make'
        self.put(self.cache,cache());self.put(self.flags,flags())
        self.compiler_file=self.work/'raylib-build/CMakeFiles/version/CMakeCCompiler.cmake'
        compiler=dict(CMAKE_C_COMPILER=str(self.compiler),CMAKE_C_COMPILER_ID='Clang',CMAKE_C_COMPILER_VERSION='test')
        self.put(self.compiler_file,''.join('set('+key+' "'+value+'")\n' for key,value in compiler.items()))
        configure=['cmake','-S',self.raylib,'-B',self.work/'raylib-build','-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_PIC=ON','-DUSE_EXTERNAL_GLFW=OFF']
        self.command('configure',configure,environment=self.env)
        self.command('archive-compiler-version',[self.compiler,'--version'],'compiler version\n',self.env)
        self.command('native-build',['cmake','--build',self.work/'raylib-build','--clean-first','--parallel','4'],environment=self.env)
        self.command('bun-version',['bun','--version'],self.lock['bun']['version']+'\n')
        self.command('clang-version',['clang','--version'],'compiler version\n',self.env)
        self.put(self.work/'qualification.c',p.QUALIFY)
        self.command('qualification-compile',self.ccommand(self.work/'qualification.c',self.work/'qualification'),environment=self.env)
        self.command('qualification',[self.work/'qualification'],json.dumps(p.QUALIFICATION)+'\n',self.env)
        native=[dict(audit.metadata(self.case,'raw'),bytes=[17,18,19]),
                dict(audit.metadata(self.case,'normalized'),bytes=[17,18,19,255]),
                dict(audit.metadata(self.case,'alias-PIC'),bytes=[17,18,19])]
        self.actions,_=audit.actions_from_native([self.case],[self.control],native)
        self.native_plan=p.plan_native_partitions([self.case]);self.plan=p.plan_partitions(self.actions)
        source=self.work/'reference-0.c';self.put(source,p.reference_program([self.case]))
        self.command('reference-0-compile',self.ccommand(source,self.work/'reference-0'),environment=self.env)
        native_text=self.frames(native);self.command('reference-0',[self.work/'reference-0'],native_text,self.env)
        self.put(self.work/'inputs.json',json.dumps(dict(cases=[self.case],controls=[self.control]),sort_keys=True)+'\n')
        lanes={lane:dict(passed=True,batches=[],differences=[]) for lane in audit.LANES}
        for index,part in enumerate(self.plan):
            selected=self.actions[part['start']:part['start']+part['count']]
            source=self.work/f'candidate-{index}.bend';binary=self.work/f'candidate-{index}';js=self.work/f'candidate-{index}.js'
            self.put(source,p.candidate_program(selected))
            self.command(f'compile-{index}',['bun',self.bend/'bend2/main.ts',source,'-o',binary,'-o',js])
            for lane in audit.LANES:
                command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
                self.command(f'{lane}-{index}',command,self.frames([item['expected'] for item in selected]))
                lanes[lane]['batches'].append(dict(part,bytes=part['compared_bytes'],passed=True))
        build_files=[self.cache,self.flags,self.compiler_file,self.compiler,self.archive]
        sources=audit.source_inventory(self.root,self.bend,self.raylib)
        for relative in sources['library']:self.reseal(self.root/relative)
        for path in sources['dependencies']:self.reseal(Path(path))
        self.report=dict.fromkeys(audit.REPORT_KEYS)
        self.report.update(passed=True,profile='native-pic-formatted-memory-v1',run_directory=str(self.work),
            reconstruction='fresh implementation; no previous runtime evidence reused',
            native_content_admission='strict global byte domain; actual PIC signature/header/all descriptors/all row packet controls and samples; malformed controls never native',
            candidate_mipmaps='implicit single-mip type contract, not stored/measured',host=dict(system='Linux',machine='test'),elapsed_seconds=0.1,
            unrun=['GPU/Metal','Windows/browser','big-endian','exact-commit hosted CI','4096x4096 allocation/resource limits','representative performance','formatted file IO','generic formatted/float dispatch','native malformed recovery'],
            toolchain=self.lock,base_revision='e'*40,reference_environment=self.env,
            tool_paths={k:str(v) for k,v in self.tools.items()},tool_realpaths={k:str(v) for k,v in self.tools.items()},
            sources=sources,inputs_sha256=audit.sha((self.work/'inputs.json').read_bytes()),
            legacy_cases=33,legacy_pixels=8867,legacy_controls=24,cases=1,pixels=1,typed_controls=1,native_rejections=0,
            batch_size=32,source_byte_limit=196608,partition_strategy='ordered-greedy-generated-source-v1',
            native_build=dict(mode='fresh-isolated-build',configuration=audit.validate_native_config(cache(),flags()),compiler=compiler,
                compiler_version='compiler version\n',artifacts={str(path):audit.sha(path.read_bytes()) for path in build_files}),
            bun_version=self.lock['bun']['version'],clang_version='compiler version',qualification=p.QUALIFICATION,
            native_partition_plan=self.native_plan,native_action_inventory=audit.inventory(audit.native_actions([self.case])),
            native_batches=[dict(self.native_plan[0],bytes=10,passed=True,output_sha256=audit.sha(native_text.encode()))],
            reference_sha256=audit.sha(native_text.encode()),native_observations=3,native_raw_bytes=3,native_normalized_bytes=4,
            native_all_observed_bytes=10,observations_per_lane=len(self.actions),compared_bytes_per_lane=36,
            raw_compared_bytes_per_lane=12,normalized_compared_bytes_per_lane=24,
            partition_plan=self.plan,action_inventory=audit.inventory(self.actions),planned_batches=len(self.plan),lanes=lanes,
            oracle_source_ranges={'src/oracle.c':dict(sha256=p.SOURCE_SHA256['src/oracle.c'],ranges=[dict(first=1,last=1,sha256=p.SOURCE_SHA256['src/oracle.c'])])},
            sealed_artifacts=self.seals)
        self.save()

    def tearDown(self):self.stack.close();self.tmp.cleanup()
    def put(self,path,value,seal=True):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value)
        if seal:self.reseal(path)
    def reseal(self,path):self.seals[str(path.resolve())]=self.a.sha(path.read_bytes())
    def save(self):self.report_path.write_text(json.dumps(self.report))
    def frames(self,rows):
        lines=[]
        for row in rows:
            lines.append(json.dumps({key:value for key,value in row.items() if key!='bytes'}))
            if 'bytes' in row:
                lines.extend(json.dumps(row['bytes'][i:i+256]) for i in range(0,len(row['bytes']),256));lines.append('"end"')
        return '\n'.join(lines)+'\n'
    def ccommand(self,source,binary):return ['clang','-std=c11','-O2','-I'+str(self.raylib/'src'),source,self.archive,'-lm','-o',binary]
    def command(self,label,command,stdout='',environment=None):
        command=list(map(str,command));files=[self.work/(label+'.stdout'),self.work/(label+'.stderr')]
        self.put(files[0],stdout);self.put(files[1],'')
        for i,value in enumerate(command[:-1]):
            if value=='-o':path=Path(command[i+1]);self.put(path,'synthetic compiler output');files.append(path)
        row=dict(command=command,reference_environment=environment,timeout_seconds=600,exit_code=0,
                 process_group_owned=True,process_group_id=12345,cleanup_timeout_seconds=5,
                 process_group_cleanup='already-exited',leader_reaped=True,cleanup_elapsed_seconds=0.01,
                 elapsed_seconds=0.02,artifacts={str(path):self.a.sha(path.read_bytes()) for path in files})
        self.put(self.work/(label+'.command.json'),json.dumps(row))
    def rewrite_output(self,label,text):
        path=self.work/(label+'.stdout');self.put(path,text)
        receipt=self.work/(label+'.command.json');row=json.loads(receipt.read_text())
        row['artifacts'][str(path)]=self.a.sha(path.read_bytes());self.put(receipt,json.dumps(row));self.save()
    def assertRejected(self):
        self.save()
        with self.assertRaises((ValueError,OSError)):self.a.audit(self.report_path)

    def test_complete_synthetic_replay_is_independent_of_harness_comparison(self):
        with ExitStack() as stack:
            for name in ('parse_rows','differences','candidate_actions','plan_partitions','validate_partitions','finish_lanes','tracked_sources'):
                stack.enter_context(patch.object(p,name,side_effect=AssertionError('audit called '+name)))
            result=self.a.audit(self.report_path)
        self.assertTrue(result['passed']);self.assertEqual(result['compared_bytes_per_lane'],36)
        self.assertEqual(result['lanes'],['cpu-1','cpu-2','javascript'])

    def test_missing_reordered_duplicate_extra_records_fail_after_resealing(self):
        label='javascript-0';good=(self.work/(label+'.stdout')).read_text();rows=[a['expected'] for a in self.actions]
        for changed in (rows[:-1],rows[::-1],rows+[rows[-1]],[rows[0],*rows],rows[1:]):
            self.rewrite_output(label,self.frames(changed));self.assertRejected()
        self.rewrite_output(label,good)
        self.assertTrue(self.a.audit(self.report_path)['passed'])

    def test_every_actual_byte_and_raw_format_is_checked_independently(self):
        original=[copy.deepcopy(a['expected']) for a in self.actions]
        for index,row in enumerate(original):
            if 'bytes' not in row:continue
            for offset in range(len(row['bytes'])):
                rows=copy.deepcopy(original);rows[index]['bytes'][offset]^=1
                self.rewrite_output('cpu-2-0',self.frames(rows));self.assertRejected()
        for key,value in [('format',7),('width',True),('height',1.0),('mipmaps',False),('extra',0)]:
            rows=copy.deepcopy(original);rows[0][key]=value
            self.rewrite_output('cpu-2-0',self.frames(rows));self.assertRejected()
        for value in (True,17.0,-1,256):
            rows=copy.deepcopy(original);rows[0]['bytes'][0]=value
            self.rewrite_output('cpu-2-0',self.frames(rows));self.assertRejected()

    def test_native_wrong_format_correct_bytes_and_normalized_bool_reject(self):
        native=[dict(self.a.metadata(self.case,'raw'),bytes=[17,18,19]),
                dict(self.a.metadata(self.case,'normalized'),bytes=[17,18,19,255]),
                dict(self.a.metadata(self.case,'alias-PIC'),bytes=[17,18,19])]
        for index,key,value in [(0,'format',7),(1,'width',True),(1,'mipmaps',1.0),(2,'format',4.0)]:
            changed=copy.deepcopy(native);changed[index][key]=value
            self.rewrite_output('reference-0',self.frames(changed));self.assertRejected()

    def test_omitted_lane_partition_source_or_action_inventory_cannot_pass(self):
        original=copy.deepcopy(self.report)
        changes=[('lanes',lambda row:row.pop('javascript')),('partition_plan',lambda rows:rows.clear()),
                 ('native_partition_plan',lambda rows:rows.clear()),('action_inventory',lambda rows:rows.pop()),
                 ('native_action_inventory',lambda rows:rows.reverse()),
                 ('sources',lambda row:row['dependencies'].pop(str(self.root/'tools/pic_format_audit.py')))]
        for key,mutate in changes:
            self.report=copy.deepcopy(original);mutate(self.report[key]);self.assertRejected()
        self.report=copy.deepcopy(original);self.report['extra']=1;self.assertRejected()

    def test_unknown_extra_stale_or_missing_seals_commands_and_sources_fail(self):
        path=self.work/'candidate-0.bend';old=path.read_text()
        path.write_text(old+'drift');self.assertRejected();path.write_text(old)
        oldseal=self.seals.pop(str(path));self.assertRejected();self.seals[str(path)]=oldseal
        self.put(self.work/'unexpected','unplanned artifact');self.assertRejected()
        self.seals.pop(str(self.work/'unexpected'));(self.work/'unexpected').unlink()
        source=self.root/'src/image.bend';source.write_text('late drift');self.reseal(source);self.assertRejected()

    def test_resealed_wrong_command_or_process_receipt_cannot_pass(self):
        path=self.work/'cpu-1-0.command.json';original=json.loads(path.read_text())
        for key,value in [('command',[str(self.work/'candidate-0'),'--gpu','off','--threads','2']),
                          ('exit_code',True),('leader_reaped',False),('process_group_owned',False),
                          ('timeout_seconds',True),('cleanup_timeout_seconds',True),('extra',0)]:
            row=copy.deepcopy(original);row[key]=value;self.put(path,json.dumps(row));self.assertRejected()

    def test_enabled_macro_cache_and_complete_build_receipt_required(self):
        good=self.flags.read_text();self.put(self.flags,good.replace(' -DSUPPORT_FILEFORMAT_PIC',''));self.assertRejected()
        self.put(self.flags,good);self.report['native_build']['mode']='reused-archive';self.assertRejected()

    def test_changed_checkout_base_overlay_and_complete_fixture_catalog_fail(self):
        path=self.root/'.git/HEAD';path.write_text('f'*40);self.assertRejected();path.write_text('e'*40)
        path=self.bend/'.git/HEAD';path.write_text('0'*40);self.assertRejected();path.write_text(self.lock['bend']['revision'])
        self.report['action_inventory'][0]['id']='unrecognized';self.assertRejected()
        self.report['action_inventory']=self.a.inventory(self.actions)
        with patch.object(p,'fixtures',return_value=[]):self.assertRejected()

    def test_declared_compiler_symlink_identity_preserved_with_resolved_seal(self):
        alias=self.root/'declared-cc';alias.symlink_to(self.compiler)
        self.put(self.compiler_file,self.compiler_file.read_text().replace(str(self.compiler),str(alias)))
        build=self.report['native_build'];build['compiler']['CMAKE_C_COMPILER']=str(alias)
        build['artifacts'][str(self.compiler_file)]=self.a.sha(self.compiler_file.read_bytes())
        build['artifacts'][str(alias)]=build['artifacts'].pop(str(self.compiler))
        receipt=self.work/'archive-compiler-version.command.json';row=json.loads(receipt.read_text())
        row['command']=[str(alias),'--version'];self.put(receipt,json.dumps(row));self.save()
        self.assertNotIn(str(alias),self.seals)
        self.assertTrue(self.a.audit(self.report_path)['passed'])

    def test_scope_provenance_and_timing_cannot_hide_false_claims(self):
        original=copy.deepcopy(self.report)
        for key,value in [('reconstruction','reused'),('native_content_admission',None),('candidate_mipmaps','measured'),
                          ('unrun',[]),('host',{'system':'Linux','machine':True}),('elapsed_seconds',True),('elapsed_seconds',-1.0)]:
            self.report=copy.deepcopy(original);self.report[key]=value;self.assertRejected()

    def test_error_payloads_duplicate_keys_nonfinite_and_short_chunks_reject(self):
        for value in ('{"a":1,"a":1}','{"a":[NaN]}','1e999','{"a":{"b":1,"b":2}}'):
            with self.assertRaises(ValueError):self.a.strict_json(value)
        action=dict(case=self.control,role='formatted-error')
        for row in [dict(id='invalid',role='formatted-error',error=True),dict(id='invalid',role='formatted-error',error=0,extra=1)]:
            with self.assertRaises(ValueError):self.a.parse_output(json.dumps(row),[action])
        case=dict(self.case,width=100);action=dict(case=case,role='raw')
        for parts in ([[0]*255,[0]*45],[[0]*257,[0]*43],[[0]*256,[],[0]*44]):
            text='\n'.join(json.dumps(value) for value in [self.a.metadata(case,'raw'),*parts,'end'])
            with self.assertRaises(ValueError):self.a.parse_output(text,[action])


if __name__=='__main__':unittest.main()
