"""Synthetic provenance/failure tests; they do not claim Darwin host execution."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools import angle_reference as angle
from tools import runtime_image as image
from test_angle_reference import AngleQualificationTests as _LinuxTests
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import modern_angle_reference as modern


def cache_image(architecture='aarch64', slide=0):
    return dict(profile='darwin-macho-shared-cache-v1', format='mach-o-64',
        architecture=architecture,endian='little',cpu_type=0x100000c if architecture=='aarch64' else 0x1000007,
        cpu_subtype=0 if architecture=='aarch64' else 3,image_uuid='1234567890abcdef'*2,
        storage='dyld-shared-cache',path='/usr/lib/system/libsystem_m.dylib',
        realpath=None,stat=None,cache_uuid='abcdef1234567890'*2,
        cache_membership=True,cache_flag=True,
        text=dict(segment='__TEXT',section='__text',vmaddr=0x180001000,size=4096,
            sha256='b'*64,protection='read-execute'),symbol_offset=32,
        observations=dict(image_base=hex(0x180000000+slide),text_address=hex(0x180001000+slide),
            symbol_address=hex(0x180001020+slide)))


def darwin_context(phase='initial',slide=0):
    return dict(kind=phase+'-context',profile='darwin-macho-runtime-image-v1',architecture='aarch64',
        endian='little',binary32=True,binary64=True,eval_method=0,rounding=0,nearest=True,
        control=0,x87_control=0,symbol='atan2f',symbol_path='volatile-pointer-equals-dlsym-default',
        runtime_image=cache_image(slide=slide),loader_overrides={key:None for key in image.DARWIN_LOADER_NAMES})


def modern_context():
    return dict(kind='qualification',rounding='FE_TONEAREST',initial_rounding=0,control=0,
        ftz=False,daz=False,binary32=True,binary64=True,excess_precision=False,
        fma_controls=9,narrow_controls=7,gradual_controls=4,
        atan2_library='/usr/lib/system/libsystem_m.dylib',fma_library='/usr/lib/system/libsystem_m.dylib',
        literal_atan2=0,pointer_atan2=0,original_atan2=0,x87_control=0,
        symbol_path='volatile-pointers-equal-dlsym-default',
        loader_overrides={key:None for key in image.DARWIN_LOADER_NAMES},
        runtime_images={key:cache_image() for key in ('atan2_library','fma_library')})


def modern_final(initial):
    return dict(kind='final-context',rounding='FE_TONEAREST',rounding_code=0,
        **{key:copy.deepcopy(initial[key]) for key in ('control','ftz','daz','runtime_images','x87_control','symbol_path','loader_overrides')})


class RuntimeImageTests(unittest.TestCase):
    def test_cache_only_never_opens_or_hashes_missing_file(self):
        meta=cache_image()
        with patch.object(Path,'read_bytes',side_effect=AssertionError('cache path is not a file')),patch.object(Path,'stat',side_effect=AssertionError('cache path is not a file')):
            result=image.enrich_image(meta)
        self.assertEqual(result['text']['sha256'],'b'*64)
        self.assertNotIn('observations',result)
        self.assertNotIn('file_sha256',result)

    def test_file_has_additional_verified_hash_stat_and_realpath(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'lib.dylib';path.write_bytes(b'synthetic ordinary-file evidence')
            st=path.stat();meta=cache_image();meta.update(profile='darwin-macho-file-v1',storage='file',path=str(path),
                realpath=str(path),stat=[st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns//10**9,st.st_mtime_ns%10**9],
                cache_membership=False,cache_flag=False,cache_uuid=None)
            self.assertEqual(image.enrich_image(meta)['file_sha256'],hashlib.sha256(path.read_bytes()).hexdigest())
            path.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'changed'):image.enrich_image(meta)

    def test_cache_membership_uuid_bounds_arch_and_schema_fail_closed(self):
        original=cache_image()
        variants=[]
        for key,value in [('cache_uuid',None),('cache_uuid','0'*32),('image_uuid',''),('image_uuid','0'*32),
                ('cache_membership',False),('cache_membership',1),('cache_flag',False),('architecture','unknown'),
                ('cpu_type',True),('cpu_type',0),('cpu_subtype',3),('endian','big'),('profile','other'),
                ('realpath','/not/a/cache/file'),('stat',[1,2,3,4,5]),('symbol_offset',4096)]:
            variants.append(dict(original,**{key:value}))
        for key,value in [('sha256',None),('sha256','0'*63),('protection','read-write-execute'),('size',0),
                          ('size',256*1024*1024+1),('vmaddr',2**64),('segment','__DATA')]:
            meta=copy.deepcopy(original);meta['text'][key]=value;variants.append(meta)
        for key in original:
            variants.append({k:v for k,v in original.items() if k!=key})
        variants.append(dict(original,unknown=True))
        for meta in variants:
            with self.subTest(meta=meta),self.assertRaises(ValueError):image.validate_image(meta)

    def test_aslr_is_only_cross_process_difference_permitted(self):
        first=cache_image();second=cache_image(slide=0x1000000)
        self.assertEqual(image.stable_image(first),image.stable_image(second))
        second['text']['sha256']='c'*64
        self.assertNotEqual(image.stable_image(first),image.stable_image(second))
        initial=darwin_context();final=darwin_context('final')
        angle.parse_context(json.dumps(initial)+'\n'+json.dumps(final))
        final['runtime_image']['text']['sha256']='c'*64
        with self.assertRaisesRegex(ValueError,'changed'):angle.parse_context(json.dumps(initial)+'\n'+json.dumps(final))
        final=darwin_context('final',0x1000000)
        with self.assertRaisesRegex(ValueError,'changed'):angle.parse_context(json.dumps(initial)+'\n'+json.dumps(final))

    def test_darwin_fenv_or_loader_failure_is_not_defaulted(self):
        for key,value in [('control',1<<24),('control',1<<19),('control',1<<22),('control',1),
                ('x87_control',1),('nearest',False),('eval_method',1),('architecture','other')]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                angle.validate_context(dict(darwin_context(),**{key:value}),'initial')
        meta=darwin_context();meta['loader_overrides']['DYLD_INSERT_LIBRARIES']='injected.dylib'
        with self.assertRaises(ValueError):angle.validate_context(meta,'initial')

    def test_modern_metadata_requires_both_initial_and_final_images(self):
        meta=modern_context();final=modern_final(meta)
        with patch.object(modern.platform,'system',return_value='Darwin'),patch.object(modern.platform,'machine',return_value='arm64'):
            modern.validate_metadata(meta);modern.validate_final_context(final);modern.validate_process_identity(meta,final)
            modern.validate_cross_process(meta,copy.deepcopy(meta))
            for key in ('runtime_images','x87_control','symbol_path','loader_overrides'):
                with self.assertRaises(ValueError):modern.validate_metadata({k:v for k,v in meta.items() if k!=key})
                with self.assertRaises(ValueError):modern.validate_final_context({k:v for k,v in final.items() if k!=key})
            changed=copy.deepcopy(final);changed['runtime_images']['fma_library']['text']['sha256']='c'*64
            with self.assertRaisesRegex(ValueError,'changed'):modern.validate_process_identity(meta,changed)
            changed=copy.deepcopy(meta);changed['runtime_images']['atan2_library']['cache_uuid']='c'*32
            with self.assertRaisesRegex(ValueError,'Mixed'):modern.validate_cross_process(meta,changed)

    def test_modern_sdk_settings_are_sealed_and_final_context_is_reobserved(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(modern.platform,'system',return_value='Darwin'):
            root=Path(tmp);sdk=root/'MacOSX.sdk';sdk.mkdir();settings=sdk/'SDKSettings.json';settings.write_text('{}')
            values={'-buildVersion':'TEST-BUILD','--show-sdk-path':str(sdk),'--show-sdk-version':'15.0'}
            calls=[]
            def run(command,work,label,**kwargs):
                calls.append(command)
                value=values[command[-1]]
                for suffix in ('.stdout','.stderr','.command.json'):
                    (Path(work)/(label+suffix)).write_text(value if suffix=='.stdout' else '{}')
                return value+'\n'
            compiler=dict(path='/compiler',sha256='e'*64,version='clang',target='arm64-apple-darwin')
            with patch.object(modern,'_run',side_effect=run),patch.object(modern,'compiler_identity',return_value=compiler):
                context,artifacts=modern.darwin_toolchain_snapshot(root,'first')
                self.assertEqual(artifacts[str(settings)],modern.sha256(settings))
                source=root/'source.c';source.write_text('original');artifacts[str(source)]=modern.sha256(source)
                native=dict(compiler=compiler,darwin_toolchain=context,artifacts=artifacts)
                modern.recheck_darwin_toolchain(native,root,'second')
                self.assertEqual(len(calls),6)
                values['--show-sdk-version']='changed'
                with self.assertRaisesRegex(ValueError,'OS/SDK identity drift'):
                    modern.recheck_darwin_toolchain(native,root,'third')
                values['--show-sdk-version']='15.0';source.write_text('changed')
                with self.assertRaisesRegex(ValueError,'artifact drift'):
                    modern.recheck_darwin_toolchain(native,root,'fourth')

    def test_modern_probe_accepts_only_named_sdk_context_artifact(self):
        import modern_angle_probe as probe
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);work=root/'work';work.mkdir();sdk=root/'MacOSX.sdk';sdk.mkdir()
            settings=sdk/'SDKSettings.json';settings.write_text('{}');sha=modern.sha256(settings)
            native=dict(system='Darwin',darwin_toolchain=dict(sdk_path=str(sdk),sdk_settings_sha256=sha),
                        artifacts={str(settings):sha})
            report={};probe.merge_native_artifacts(report,native,work)
            self.assertEqual(report['native_context_artifacts'],{str(settings):sha})
            native['system']='Linux'
            with self.assertRaisesRegex(ValueError,'outside evidence'):
                probe.merge_native_artifacts({},native,work)
            native['system']='Darwin';settings.write_text('changed')
            with self.assertRaisesRegex(ValueError,'SDK settings artifact drift'):
                probe.merge_native_artifacts({},native,work)

    def test_modern_recheck_is_fresh_and_rejects_code_drift(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(modern.platform,'system',return_value='Darwin'),patch.object(modern.platform,'machine',return_value='arm64'):
            binary=Path(tmp)/'reference';binary.write_text('attestation binary fixture')
            environment=modern_context()
            native=dict(binary=str(binary),environment=environment,
                        reference_environment=modern.reference_environment.ReferenceEnvironment().receipt(),artifacts={str(binary):modern.sha256(binary)},
                        libraries=image.enrich_images(environment['runtime_images']))
            calls=[]
            def run(command,work,label,**kwargs):
                calls.append(command)
                final=modern_final(environment)
                (Path(work)/(label+'.stderr')).write_text(json.dumps(final)+'\n')
                (Path(work)/(label+'.stdout')).write_text(json.dumps(environment)+'\n')
                (Path(work)/(label+'.command.json')).write_text('{}\n')
                return json.dumps(environment)
            with patch.object(modern,'_run',side_effect=run),patch.object(modern,'recheck_darwin_toolchain') as toolchain_check:
                modern.recheck_runtime_libraries(native)
                self.assertEqual(calls,[[binary,'--qualify']])
                self.assertEqual(len(native['runtime_rechecks']),1)
                toolchain_check.assert_called_once()
                environment=copy.deepcopy(environment);environment['runtime_images']['atan2_library']['text']['sha256']='c'*64
                with self.assertRaisesRegex(ValueError,'Mixed|drift'):modern.recheck_runtime_libraries(native)
                binary.write_text('stale executable mutated')
                with self.assertRaisesRegex(ValueError,'artifact drift'):modern.recheck_runtime_libraries(native)
                self.assertEqual(len(calls),2)


# Reuse protocol setup, without inheriting/discovering the Linux-only test cases.
class DarwinQualificationTests(unittest.TestCase):
    setUp=_LinuxTests.setUp
    failed=_LinuxTests.failed
    linux_runner=_LinuxTests.runner

    def qualify(self, mutate=None, profile='Apple2007AngleRn'):
        self.profile=profile
        sdk=self.root/'MacOSX.sdk';sdk.mkdir(exist_ok=True);(sdk/'SDKSettings.json').write_text('{}')
        def runner(command,**kwargs):
            if '-###' in command: return subprocess.CompletedProcess(command,0,'','observed compiler invocation')
            if Path(command[0]).name=='sw_vers': return subprocess.CompletedProcess(command,0,'TEST-BUILD\n','')
            if Path(command[0]).name=='xcrun':
                return subprocess.CompletedProcess(command,0,(str(sdk) if '--show-sdk-path' in command else 'TEST-SDK')+'\n','')
            def replace(initial,final,label):
                initial.clear();final.clear()
                slide=len(self.commands)*0x100000
                initial.update(darwin_context('initial',slide));final.update(darwin_context('final',slide))
                if mutate:mutate(initial,final,label)
            self.bad_meta=replace
            return self.linux_runner(command,**kwargs)
        def which(name):return str(self.compiler) if name=='clang' else '/mock/bin/'+name
        with patch.object(angle,'load_manifest',return_value=copy.deepcopy(self.manifest)),patch.object(angle.shutil,'which',side_effect=which),patch.object(angle.platform,'system',return_value='Darwin'),patch.object(angle.platform,'machine',return_value='arm64'),patch.dict(angle.os.environ,{},clear=True):
            return angle.qualify(self.raylib,self.library,self.root,c_source=angle_conformance.c_source,
                cases_from=angle_conformance.cases_from,parse_output=angle_conformance.parse_output,runner=runner)

    def test_all_five_native_contexts_select_from_words_not_darwin_name(self):
        for profile in angle.PROFILES:
            result=self.qualify(profile=profile)
            self.assertEqual(result['selected_profile'],profile)
            self.assertEqual(len(result['contexts']),5)
            self.assertNotIn('dpkg-query',' '.join(' '.join(c) for c in self.commands))
            self.assertNotIn('readelf',' '.join(' '.join(c) for c in self.commands))

    def test_mixed_image_contexts_and_cache_missing_fail_stale_receipt(self):
        def mixed(i,f,label):
            if label=='runtime-wrapper':
                i['runtime_image']['text']['sha256']=f['runtime_image']['text']['sha256']='c'*64
        for mutate in (mixed,lambda i,f,l:i['runtime_image'].update(cache_membership=False),
                       lambda i,f,l:i.update(control=1<<24)):
            with self.assertRaises(ValueError):self.qualify(mutate)
            self.failed()

    def test_numeric_mismatch_still_blocks_candidate(self):
        self.outputs['pointer']='[]\n'
        with self.assertRaises(ValueError):self.qualify()
        self.failed()


from tools import conformance as angle_conformance
# Avoid unittest rediscovering this imported class in this module.
del _LinuxTests
