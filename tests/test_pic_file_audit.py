"""Source-only complete file-audit replay and adversarial receipt tests.

All executable outputs are synthetic fixtures. No native/candidate build is
started and successful replay is evidence of audit mechanics, not parity.
"""
import copy
from contextlib import ExitStack
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pic_file_audit as a
import pic_file_probe as p
import pic_format_probe as memory
from r32_raw_file_probe import RESOURCE_RUNNER


class PicFileCasefoldInventoryTests(unittest.TestCase):
    def test_same_bytes_through_casefold_alias_still_fail_exact_inventory(self):
        # Simulate case-insensitive reads on a case-sensitive temporary tree.
        # This tests the existing auditor, not macOS/native qualification.
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);work=root/'work';fixtures=work/'fixtures';fixtures.mkdir(parents=True)
            cases=[];seals={};aliases={}
            for channels in (3,4):
                for suffix in ('pnm','qoi'):
                    lower=f'path-c{channels}-{suffix}.{suffix}'
                    upper=f'path-c{channels}-{suffix.upper()}.{suffix.upper()}'
                    physical=fixtures/lower;physical.write_bytes(b'unchanged fixture bytes')
                    aliases[fixtures/upper]=physical
                    for name in (lower,upper):
                        path=fixtures/name
                        cases.append(dict(filename=name,path=str(path.relative_to(root)),bytes=list(physical.read_bytes())))
                        seals[str(path)]=a.sha(physical.read_bytes())
            stress=fixtures/'exact-cap.pic';stress.write_bytes(b'stress')
            seals[str(stress)]=a.sha(stress.read_bytes())
            inputs=dict(cases=cases,controls=[],exact_cap=dict(path=str(stress.relative_to(root)),bytes=list(stress.read_bytes())))
            read_bytes=Path.read_bytes;is_file=Path.is_file
            with patch.object(Path,'read_bytes',lambda path:read_bytes(aliases.get(path,path))),\
                 patch.object(Path,'is_file',lambda path:is_file(aliases.get(path,path))):
                with self.assertRaisesRegex(ValueError,'complete fixture file inventory'):
                    a.verify_files(inputs,root,work,seals)


class PicFileAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.work=self.root/'evidence'/('run-'+'0'*32);self.work.mkdir(parents=True)
        self.report_path=self.work.parent/'results.json';self.seals={};self.stack=ExitStack()
        original_root=p.ROOT
        originals={c['id']:c for c in p.fixtures()}
        cases=[originals['c3-single'],originals['c4-single'],dict(originals['c3-single'],id='explicit',filename='explicit.dat',route='explicit-pic')]
        controls=[c for c in p.controls() if c['id'] in ('not-pic-qoi','directory','cap-plus-one','host-size-overflow','missing')]
        synthetic=[dict(id='u32-control',bytes=[256],error=1)]
        self.lock=json.loads((original_root/'toolchain.json').read_text())
        self.bend=self.root/'bend';self.raylib=self.root/'raylib'
        for root,revision in ((self.root,'e'*40),(self.bend,self.lock['bend']['revision']),(self.raylib,self.lock['raylib']['revision'])):
            self.put(root/'.git/HEAD',revision,False)
        dependencies=('tools/pic_format_probe.py','tools/pic_format_audit.py','tests/test_pic_format_harness.py','tools/pic_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','LAWS.bend','PROOF.bend','tools/pic_file_probe.py','tools/pic_file_audit.py','tests/test_pic_file_harness.py','tests/test_pic_file_audit.py','tools/raw_file_probe.py','tools/r32_raw_file_probe.py','tools/png_probe.py','tools/qoi_format_probe.py','tools/tga_format_probe.py','tools/tga_probe.py')
        for relative in (*dependencies,'jonmath.bend','src/image.bend'):
            self.put(self.root/relative,'synthetic source\n')
        self.put(self.root/'jonlib.bend',(original_root/'jonlib.bend').read_text())
        self.put(self.bend/'bend2/main.ts','synthetic compiler\n')
        self.put(self.raylib/'src/oracle.c','synthetic oracle\n')
        for relative in self.lock['bend']['patch']['files']:
            self.put(self.bend/relative,'synthetic overlay\n',False)
            self.lock['bend']['patch']['files'][relative]=a.sha((self.bend/relative).read_bytes())
        overlay=self.root/self.lock['bend']['patch']['path'];self.put(overlay,'synthetic patch\n',False)
        self.lock['bend']['patch']['sha256']=a.sha(overlay.read_bytes())
        self.put(self.root/'toolchain.json',json.dumps(self.lock))
        # Shorten only the unused synthetic exact-cap tail. These records exercise
        # replay mechanics, never actual allocation or native parity.
        self.stack.enter_context(patch.object(a,'CAP',256))
        self.stack.enter_context(patch.object(p,'PIC_CAP',256))
        self.stack.enter_context(patch.object(p,'ROOT',self.root))
        self.stack.enter_context(patch.object(p,'fixtures',return_value=cases))
        self.stack.enter_context(patch.object(p,'controls',return_value=controls))
        self.stack.enter_context(patch.object(p,'synthetic_controls',return_value=synthetic))
        self.stack.enter_context(patch.object(memory,'SOURCE_RANGES',{'src/oracle.c':[(1,1)]}))
        self.stack.enter_context(patch.object(memory,'SOURCE_SHA256',{'src/oracle.c':a.sha((self.raylib/'src/oracle.c').read_bytes())}))
        self.stack.enter_context(patch.object(p,'FILE_SOURCE_RANGES',{}))
        self.inputs=a.expected_inputs(p,self.root,self.work)
        self.cases=self.inputs['cases'];self.controls=self.inputs['controls'];self.stress=self.inputs['exact_cap']
        for c in self.cases+self.controls+[self.stress]:
            path=self.root/c['path'];special=c.get('special')
            if special=='missing':continue
            path.parent.mkdir(parents=True,exist_ok=True)
            if special=='directory':path.mkdir();(path/'entry').write_bytes(b'x')
            elif special in ('sparse','large','overflow'):
                with path.open('wb') as f:f.write(bytes(c['prefix']));f.truncate(c['size'])
            else:path.write_bytes(bytes(c['bytes']));self.reseal(path)
        self.put(self.work/'inputs.json',json.dumps(self.inputs))
        self.environment=p.ReferenceEnvironment('clean-loader').receipt()
        self.tools={k:self.root/k for k in ('bun','clang','cmake','python')}
        for k,path in self.tools.items():self.put(path,'synthetic executable '+k)
        self.compiler=self.tools['clang'];self.archive=self.work/'raylib-build/raylib/libraylib.a'
        self.put(self.archive,'synthetic archive')
        self.cache=self.work/'raylib-build/CMakeCache.txt';self.flags=self.work/'raylib-build/raylib/CMakeFiles/raylib.dir/flags.make'
        base=dict(PLATFORM='Memory',CMAKE_BUILD_TYPE='Release',CUSTOMIZE_BUILD='ON',SUPPORT_MODULE_RAUDIO='OFF',BUILD_EXAMPLES='OFF',USE_EXTERNAL_GLFW='OFF')
        base.update({'SUPPORT_FILEFORMAT_'+n:'ON' for n in a.ALIAS_MACROS})
        self.put(self.cache,''.join(k+':STRING='+v+'\n' for k,v in base.items()))
        self.put(self.flags,'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY '+' '.join('-DSUPPORT_FILEFORMAT_'+n for n in a.ALIAS_MACROS)+'\n')
        self.compiler_file=self.work/'raylib-build/CMakeFiles/version/CMakeCCompiler.cmake'
        compiler=dict(CMAKE_C_COMPILER=str(self.compiler),CMAKE_C_COMPILER_ID='Clang',CMAKE_C_COMPILER_VERSION='test')
        self.put(self.compiler_file,''.join('set('+k+' "'+v+'")\n' for k,v in compiler.items()))
        configure=['cmake','-S',self.raylib,'-B',self.work/'raylib-build','-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_PIC=ON','-DUSE_EXTERNAL_GLFW=OFF']+['-DSUPPORT_FILEFORMAT_'+n+'=ON' for n in a.ALIAS_MACROS if n!='PIC']
        self.command('configure',configure,environment=self.environment)
        self.command('archive-compiler-version',[self.compiler,'--version'],'compiler version\n',self.environment)
        self.command('native-build',['cmake','--build',self.work/'raylib-build','--clean-first','--parallel','4'],environment=self.environment)
        self.command('bun-version',['bun','--version'],self.lock['bun']['version']+'\n')
        self.command('clang-version',['clang','--version'],'compiler version\n',self.environment)
        self.put(self.work/'qualification.c',p.qualification_program())
        self.command('qualification-compile',self.ccommand(self.work/'qualification.c',self.work/'qualification'),environment=self.environment)
        self.command('qualification',[self.work/'qualification'],json.dumps(memory.QUALIFICATION)+'\n',self.environment)
        self.native=self.native_rows(self.cases)
        self.actions,self.references=a.actions_from_native(self.cases,self.controls,self.native,synthetic)
        self.native_plan=a.plan(self.cases,p.reference_program,True);self.plan=a.plan(self.actions,p.candidate_program)
        native_batches=[];outputs=[]
        for index,part in enumerate(self.native_plan):
            selected=self.cases[part['start']:part['start']+part['count']]
            source=self.work/f'reference-{index}.c';binary=self.work/f'reference-{index}'
            self.put(source,p.reference_program(selected));self.command(f'reference-{index}-compile',self.ccommand(source,binary),environment=self.environment)
            text=self.frames(self.native_rows(selected));outputs.append(text)
            self.command(f'reference-{index}',[binary],text,self.environment)
            native_batches.append(dict(part,bytes=part['compared_bytes'],passed=True,output_sha256=a.sha(text.encode())))
        self.stress_rows=self.native_rows([self.stress]);text=self.frames(self.stress_rows)
        source=self.work/'exact-cap-reference.c';self.put(source,p.reference_program([self.stress]))
        self.command('exact-cap-reference-compile',self.ccommand(source,self.work/'exact-cap-reference'),environment=self.environment)
        self.command('exact-cap-reference',[self.work/'exact-cap-reference'],text,self.environment)
        lanes={lane:dict(passed=True,batches=[],differences=[]) for lane in a.LANES}
        for index,part in enumerate(self.plan):
            selected=self.actions[part['start']:part['start']+part['count']]
            source=self.work/f'candidate-{index}.bend';binary=self.work/f'candidate-{index}';js=self.work/f'candidate-{index}.js'
            self.put(source,p.candidate_program(selected));self.command(f'compile-{index}',['bun',self.bend/'bend2/main.ts',source,'-o',binary,'-o',js])
            for lane in a.LANES:
                command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
                self.command(f'{lane}-{index}',command,self.frames([item['expected'] for item in selected]))
                lanes[lane]['batches'].append(dict(part,bytes=part['compared_bytes'],passed=True))
        stress_actions,_=a.actions_from_native([self.stress],[],self.stress_rows)
        self.resources=dict(boundary=a.boundary_actions(self.cases,self.controls,self.references),sparse=[dict(case=c,role='formatted-error',expected=a.metadata(c,'formatted-error')) for c in self.controls if c.get('special') in ('sparse','large','overflow')],exact_cap=stress_actions)
        for kind,actions in self.resources.items():
            program=p.boundary_program(self.cases,self.controls) if kind=='boundary' else p.candidate_program(actions)
            source=self.work/(kind+'.bend');binary=self.work/kind;js=self.work/(kind+'.js')
            self.put(source,program);self.command(kind+'-compile',['bun',self.bend/'bend2/main.ts',source,'-o',binary,'-o',js])
            output=self.frames([x['expected'] for x in actions])+(json.dumps(a.TERMINAL)+'\n' if kind=='boundary' else '')
            for lane in a.LANES:
                label=lane+'-'+kind;launcher=self.work/(label+'.resource-runner.py');usage=self.work/(label+'.resource.json')
                self.put(launcher,'import resource\nresource.setrlimit(resource.RLIMIT_NOFILE,(64,64))\n'+RESOURCE_RUNNER)
                self.put(usage,json.dumps(dict(maximum_rss_bytes=123456)))
                command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
                self.command(label,[self.tools['python'],launcher,usage,*command],output,timeout=240)
                lanes[lane][kind]=dict(passed=True,maximum_rss_bytes=123456,elapsed_seconds=0.1,descriptor_limit=64,maximum_rss_acceptance_bytes=a.MAX_STRESS_RSS if kind=='exact_cap' else a.MAX_SPARSE_RSS,**a.resource_plan(actions),stdout_sha256=a.sha(output.encode()))
        sources=a.source_inventory(self.root,self.bend,self.raylib)
        for relative in sources['library']:self.reseal(self.root/relative)
        for path in sources['dependencies']:self.reseal(Path(path))
        files=[self.cache,self.flags,self.compiler_file,self.compiler,self.archive]
        self.report=dict.fromkeys(a.REPORT_KEYS)
        self.report.update(passed=True,profile='native-pic-formatted-files-v1',evidence_origin='NEW source-scoped file run; earlier memory evidence remains separate',run_directory=str(self.work),toolchain=self.lock,base_revision='e'*40,host=dict(system=a.platform.system(),machine='test'),tool_paths={k:str(v) for k,v in self.tools.items()},tool_realpaths={k:str(v) for k,v in self.tools.items()},sources=sources,reference_environment=self.environment,inputs_sha256=a.sha((self.work/'inputs.json').read_bytes()),native_content_admission='unchanged PIC memory admission: actual header/all descriptors/all row controls/counts/samples; malformed and overcap controls never native; native suffix shares stb sniffing',cases=len(self.cases),pixels=3,typed_controls=len(self.controls)+len(synthetic),file_controls=len(self.controls),synthetic_controls=len(synthetic),native_rejections=0,native_routes={'LoadImage':2,'explicit-pic':1},batch_size=32,source_byte_limit=196608,partition_strategy='ordered-greedy-generated-source-v1',lanes=lanes,candidate_mipmaps='implicit single-mip type contract, not stored/measured',factory_role='native-byte factory reconstruction gated by a distinct successful public reopen; not a second loader-byte comparison',raw_roundtrip_role='reopened loader bytes exported and reconstructed through from_bytes',closure=a.TERMINAL,file_descriptor_limit=64,host_directory_observation=dict(stage='read',code=p.errno.EISDIR,message=p.os.strerror(p.errno.EISDIR)),boundary_source_contract=a.boundary_source_contract(self.root),unrun=['GPU/Metal','Windows/macOS/browser','big-endian','exact-commit hosted CI','maximum-area allocation/resource limits','representative performance','concurrent/special files','OS close-error reporting','generic formatted/float dispatch','native malformed recovery'],native_build=dict(mode='fresh-isolated-build',configuration=a.validate_native_config(self.cache.read_text(),self.flags.read_text()),compiler=compiler,compiler_version='compiler version\n',artifacts={str(path):a.sha(path.read_bytes()) for path in files},file_aliases=a.validate_alias_config(self.cache.read_text(),self.flags.read_text())),bun_version=self.lock['bun']['version'],clang_version='compiler version',qualification=memory.QUALIFICATION,native_partition_plan=self.native_plan,native_action_inventory=a.inventory(a.native_actions(self.cases)),native_batches=native_batches,reference_sha256=a.sha(''.join(outputs).encode()),partitions=self.plan,action_inventory=a.inventory(self.actions),native_observations=len(self.native),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in self.references.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in self.references.values()),observations_per_lane=len(self.actions),compared_bytes_per_lane=sum(len(x['expected'].get('bytes',[])) for x in self.actions),raw_compared_bytes_per_lane=sum(len(x['expected'].get('bytes',[])) for x in self.actions if x['role'] in a.RAW),normalized_compared_bytes_per_lane=sum(len(x['expected'].get('bytes',[])) for x in self.actions if x['role'] not in a.RAW),exact_cap=dict(size=a.CAP,native_reference=self.stress_rows[0],native_normalized=self.stress_rows[1]),resource_plans={k:a.resource_plan(v) for k,v in self.resources.items()},elapsed_seconds=0.2,sealed_artifacts=self.seals,oracle_source_ranges={'src/oracle.c':dict(sha256=memory.SOURCE_SHA256['src/oracle.c'],ranges=[dict(first=1,last=1,sha256=memory.SOURCE_SHA256['src/oracle.c'])])})
        self.report['exact-cap-reference_sha256']=a.sha(self.frames(self.stress_rows).encode());self.save()

    def tearDown(self):self.stack.close();self.tmp.cleanup()
    def put(self,path,value,seal=True):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value)
        if seal:self.reseal(path)
    def reseal(self,path):self.seals[str(path.resolve())]=a.sha(path.read_bytes())
    def save(self):self.report_path.write_text(json.dumps(self.report))
    def native_rows(self,cases):
        return [dict(a.metadata(c,role),bytes=([17,18,19] if c['channels']==3 and role=='raw' else [17,18,19,255])) for c in cases for role in ('raw','normalized')]
    def frames(self,rows):
        lines=[]
        for row in rows:
            lines.append(json.dumps({k:v for k,v in row.items() if k!='bytes'}))
            if 'bytes' in row:
                lines.extend(json.dumps(row['bytes'][i:i+256]) for i in range(0,len(row['bytes']),256));lines.append('"end"')
        return '\n'.join(lines)+'\n'
    def ccommand(self,source,binary):return ['clang','-std=c11','-O2','-I'+str(self.raylib/'src'),source,self.archive,'-lm','-o',binary]
    def command(self,label,command,stdout='',environment=None,timeout=600):
        command=list(map(str,command));files=[self.work/(label+'.stdout'),self.work/(label+'.stderr')]
        self.put(files[0],stdout);self.put(files[1],'')
        for i,value in enumerate(command[:-1]):
            if value=='-o':path=Path(command[i+1]);self.put(path,'synthetic compiler output');files.append(path)
        self.put(self.work/(label+'.command.json'),json.dumps(dict(command=command,reference_environment=environment,timeout_seconds=timeout,exit_code=0,process_group_owned=True,process_group_id=12345,cleanup_timeout_seconds=5,process_group_cleanup='already-exited',leader_reaped=True,cleanup_elapsed_seconds=0.01,elapsed_seconds=0.02,artifacts={str(path):a.sha(path.read_bytes()) for path in files})))
    def rewrite_output(self,label,text):
        path=self.work/(label+'.stdout');self.put(path,text)
        receipt=self.work/(label+'.command.json');row=json.loads(receipt.read_text())
        row['artifacts'][str(path)]=a.sha(path.read_bytes());self.put(receipt,json.dumps(row));self.save()
    def assertRejected(self):
        self.save()
        with self.assertRaises((ValueError,OSError)):a.audit(self.report_path)

    def test_complete_replay_does_not_use_harness_comparators_or_action_construction(self):
        with ExitStack() as stack:
            for module,names in ((p,('candidate_actions','boundary_actions','parse_boundary','plan_partitions','validate_partitions','finish_lanes','tracked_sources','resource_plan')),(memory,('parse_rows','differences','candidate_actions','actions_from_native'))):
                for name in names:
                    if hasattr(module,name):stack.enter_context(patch.object(module,name,side_effect=AssertionError('forbidden shared comparator '+name)))
            stack.enter_context(patch('subprocess.run',side_effect=AssertionError('auditor ran process')))
            result=a.audit(self.report_path)
        self.assertTrue(result['passed']);self.assertEqual(result['resource_observations']['boundary'],1009)

    def test_resealed_missing_reordered_extra_candidate_and_native_records_reject(self):
        for label,rows in (('javascript-0',[x['expected'] for x in self.actions]),('reference-0',self.native),('exact-cap-reference',self.stress_rows)):
            good=(self.work/(label+'.stdout')).read_text()
            for changed in (rows[:-1],rows[::-1],rows+[rows[-1]],[rows[0],*rows]):
                self.rewrite_output(label,self.frames(changed));self.assertRejected()
            self.rewrite_output(label,good)

    def test_every_byte_and_metadata_checked_after_resealing(self):
        original=[copy.deepcopy(x['expected']) for x in self.actions]
        for index,row in enumerate(original):
            if 'bytes' not in row:continue
            for offset in range(len(row['bytes'])):
                rows=copy.deepcopy(original);rows[index]['bytes'][offset]^=1
                self.rewrite_output('cpu-2-0',self.frames(rows));self.assertRejected()
        for key,value in (('format',7),('width',True),('height',1.0),('mipmaps',False),('extra',0)):
            rows=copy.deepcopy(original);rows[0][key]=value
            self.rewrite_output('cpu-2-0',self.frames(rows));self.assertRejected()
        for value in (True,17.0,-1,256):
            rows=copy.deepcopy(original);rows[0]['bytes'][0]=value
            self.rewrite_output('cpu-2-0',self.frames(rows));self.assertRejected()

    def test_all_resource_bytes_errors_stages_and_terminal_replayed(self):
        for kind,actions in self.resources.items():
            label='javascript-'+kind;good=(self.work/(label+'.stdout')).read_text()
            original=[copy.deepcopy(x['expected']) for x in actions]
            indexes=range(len(original)) if kind!='boundary' else (0,1,2,7,8,9,10,11,12,13,14,15,16,17,508,1008)
            for index in indexes:
                rows=copy.deepcopy(original)
                if 'bytes' in rows[index]:rows[index]['bytes'][-1]^=1
                else:rows[index]['error']^=1
                output=self.frames(rows)+(json.dumps(a.TERMINAL)+'\n' if kind=='boundary' else '')
                self.rewrite_output(label,output);self.assertRejected()
            self.rewrite_output(label,good)
        good=(self.work/'cpu-1-boundary.stdout').read_text()
        self.rewrite_output('cpu-1-boundary',json.dumps(a.TERMINAL)+'\n');self.assertRejected()
        terminal=dict(a.TERMINAL,iterations=True)
        self.rewrite_output('cpu-1-boundary','\n'.join(good.splitlines()[:-1])+'\n'+json.dumps(terminal)+'\n');self.assertRejected()

    def test_sparse_holes_never_read_or_hashed_even_if_maliciously_sealed(self):
        sparse={self.root/c['path'] for c in self.controls if c.get('special') in ('sparse','large','overflow')}
        original=Path.read_bytes
        def guarded(path):
            if path in sparse:raise AssertionError('sparse full read')
            return original(path)
        with patch.object(Path,'read_bytes',guarded):
            self.assertTrue(a.audit(self.report_path)['passed'])
            self.seals[str(next(iter(sparse)))]= '0'*64;self.assertRejected()

    def test_sparse_size_prefix_and_file_drift_reject(self):
        sparse=next(self.root/c['path'] for c in self.controls if c.get('special')=='sparse')
        with sparse.open('r+b') as f:f.write(b'!')
        self.assertRejected()

    def test_schema_lane_partition_inventory_and_source_omissions_reject(self):
        original=copy.deepcopy(self.report)
        for key,mutate in (('lanes',lambda x:x.pop('javascript')),('partitions',lambda x:x.clear()),('native_partition_plan',lambda x:x.clear()),('action_inventory',lambda x:x.pop()),('native_action_inventory',lambda x:x.reverse()),('resource_plans',lambda x:x.pop('sparse')),('sources',lambda x:x['dependencies'].pop(str(self.root/'tools/pic_file_audit.py')))):
            self.report=copy.deepcopy(original);mutate(self.report[key]);self.assertRejected()
        self.report=copy.deepcopy(original);self.report['unknown']=1;self.assertRejected()

    def test_effective_alias_configuration_rejects_disabled_redefined_and_comment_flags(self):
        cache=self.cache.read_text();flags=self.flags.read_text()
        for macro in ('SUPPORT_FILEFORMAT_'+n for n in a.ALIAS_MACROS):
            for changed in (flags.replace('-D'+macro,''),flags+' -U'+macro,flags+' -D'+macro+'=0',flags.replace('-D'+macro,'# -D'+macro+'\n')):
                with self.assertRaises(ValueError):a.validate_alias_config(cache,changed)
            with self.assertRaises(ValueError):a.validate_alias_config(cache.replace(macro+':STRING=ON',macro+':STRING=OFF'),flags)

    def test_resource_limits_command_provenance_and_cleanup_reject(self):
        path=self.work/'cpu-1-boundary.command.json';original=json.loads(path.read_text())
        for key,value in (('command',[str(self.tools['python']),'wrong']),('exit_code',True),('leader_reaped',False),('process_group_owned',False),('timeout_seconds',600),('cleanup_timeout_seconds',True),('process_group_id',True),('reference_environment',self.environment)):
            row=copy.deepcopy(original);row[key]=value;self.put(path,json.dumps(row));self.assertRejected()
        self.put(path,json.dumps(original))
        resource=self.report['lanes']['cpu-1']['boundary'];saved=copy.deepcopy(resource)
        for key,value in (('descriptor_limit',65),('maximum_rss_bytes',True),('maximum_rss_acceptance_bytes',a.MAX_STRESS_RSS),('observations',True),('elapsed_seconds',-0.1)):
            resource.clear();resource.update(saved);resource[key]=value;self.assertRejected()

    def test_resource_launcher_cannot_omit_rlimit_or_change_measured_command(self):
        path=self.work/'cpu-1-sparse.resource-runner.py';good=path.read_text()
        self.put(path,good.replace('resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))','pass'));self.assertRejected()

    def test_unknown_unsealed_stale_artifacts_and_sources_fail_closed(self):
        path=self.work/'candidate-0.bend';good=path.read_text();path.write_text(good+'drift');self.assertRejected();path.write_text(good)
        seal=self.seals.pop(str(path));self.assertRejected();self.seals[str(path)]=seal
        self.put(self.work/'unexpected','unplanned');self.assertRejected()

    def test_fixture_byte_identity_native_route_and_synthetic_u32_identity_are_bound(self):
        original=copy.deepcopy(self.inputs)
        for mutate in (lambda x:x['cases'][0].update(route='explicit-pic'),lambda x:x['cases'][0]['bytes'].__setitem__(-1,0),lambda x:x['synthetic_controls'][0]['bytes'].__setitem__(0,0),lambda x:x['exact_cap']['bytes'].pop()):
            data=copy.deepcopy(original);mutate(data);self.put(self.work/'inputs.json',json.dumps(data));self.report['inputs_sha256']=a.sha((self.work/'inputs.json').read_bytes());self.assertRejected()

    def test_supported_host_profile_and_same_host_replay_required(self):
        original=copy.deepcopy(self.report['host'])
        for system in ('Linux','Darwin'):
            self.report['host']=dict(system=system,machine='test');self.save()
            with patch.object(a.platform,'system',return_value=system):
                self.assertTrue(a.audit(self.report_path)['passed'])
            with patch.object(a.platform,'system',return_value='Darwin' if system=='Linux' else 'Linux'):
                self.assertRejected()
        for host in (dict(system='Windows',machine='test'),dict(system='Plan9',machine='test'),dict(system=True,machine='test'),dict(system=original['system'],machine=True),dict(original,extra=1)):
            self.report['host']=host;self.assertRejected()

    def test_strict_json_full_chunks_errors_and_types(self):
        for value in ('{"a":1,"a":1}','{"a":[NaN]}','1e999','{"a":{"b":1,"b":2}}'):
            with self.assertRaises(ValueError):a.strict_json(value)
        case=dict(self.cases[0],width=100);action=dict(case=case,role='raw')
        for chunks in (([0]*255,[0]*45),([0]*257,[0]*43),([0]*256,[],[0]*44)):
            text='\n'.join(json.dumps(row) for row in [a.metadata(case,'raw'),*chunks,'end'])
            with self.assertRaises(ValueError):a.parse_output(text,[action])
        for value in (True,1.0):
            with self.assertRaises(ValueError):a.equal({'x':[value]},{'x':[1]},'strict recursive type')


class PicFileAuditCorpusTests(unittest.TestCase):
    def test_production_corpus_independent_roles_resources_and_plans(self):
        self.assertEqual(a.CAP,1048576)
        cases,controls,synthetic=p.fixtures(),p.controls(),p.synthetic_controls()
        for case in cases+controls:case['path']='build/audit-unit/fixtures/'+case['filename']
        native=[dict(a.metadata(c,role),bytes=[17]*(c['width']*c['height']*(c['channels'] if role=='raw' else 4))) for c in cases for role in ('raw','normalized')]
        independent,references=a.actions_from_native(cases,controls,native,synthetic)
        harness=p.candidate_actions(cases,controls,references,synthetic)
        a.equal(independent,harness,'independent production actions')
        a.equal(a.boundary_actions(cases,controls,references),p.boundary_actions(cases,controls,references),'independent production closure')
        a.equal(a.plan(cases,p.reference_program,True),p.plan_native_partitions(cases),'independent production native partitions')
        a.equal(a.plan(independent,p.candidate_program),p.plan_partitions(harness),'independent production candidate partitions')
        self.assertEqual((len(cases),sum(c['width']*c['height'] for c in cases),len(independent)),(170,37375,1724))
        self.assertEqual(sum(len(x['expected'].get('bytes',[])) for x in independent),830752)
        self.assertEqual(sum(len(x['expected'].get('bytes',[])) for x in a.boundary_actions(cases,controls,references)),703)


if __name__=='__main__':unittest.main()
