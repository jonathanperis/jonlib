"""Independent native qualification: compiler-free protocol/failure regression."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from tools import conformance
from tools import angle_reference as angle


def scalar_rows(manifest, profile):
    return [dict(id=r['id'], y=r['y'], x=r['x'], result=r['expected'][profile]) for r in manifest['scalar_controls']]


def wrapper_rows(manifest, profile):
    return [dict(id=r['id'], width=1, height=1, pixels=[int(r['expected'][profile],16)]) for r in manifest['wrapper_controls']]


def context(library, phase='initial'):
    st = library.stat()
    return dict(kind=phase+'-context', profile='linux-glibc-elf-runtime-image-v1', architecture='x86_64',
                endian='little', binary32=True, binary64=True, eval_method=0, rounding=0, nearest=True,
                control=8064, x87_control=895, libc_version='2.41', symbol='atan2f',
                symbol_path='volatile-pointer-equals-dlsym-default', library_path=str(library),
                library_realpath=str(library), library_build_id='12345678abcdef00',
                library_stat=[st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns//10**9,st.st_mtime_ns%10**9],
                loader_overrides={key:None for key in angle.LOADER_NAMES})


class FrozenAngleTests(unittest.TestCase):
    def setUp(self):
        self.manifest=angle.load_manifest()
        self.cases=conformance.cases_from(angle.control_document(self.manifest))

    def test_controls_unique_and_three_signatures_separated(self):
        self.assertEqual(len(self.manifest['scalar_controls']),76)
        self.assertEqual(len(self.manifest['wrapper_controls']),205)
        for profile in angle.PROFILES:
            matches, _=angle.match_profiles(self.manifest,scalar_rows(self.manifest,profile),wrapper_rows(self.manifest,profile))
            self.assertEqual(matches,[profile])

    def test_duplicate_profiles_are_ambiguous(self):
        profile=angle.PROFILES[0]
        matches,_=angle.match_profiles(self.manifest,scalar_rows(self.manifest,profile),wrapper_rows(self.manifest,profile),(profile,profile))
        self.assertEqual(matches,[profile,profile])

    def test_mixed_signs_scales_apis_contexts_and_one_ulp_rejected(self):
        for profile in angle.PROFILES:
            scalar=scalar_rows(self.manifest,profile); wrappers=wrapper_rows(self.manifest,profile)
            for group, original in [('scalar',scalar),('wrapper',wrappers)]:
                # Every position includes all sign/scale/API families.
                for index in range(len(original)):
                    changed=copy.deepcopy(original)
                    if group=='scalar': changed[index]['result']=f"{int(changed[index]['result'],16)^1:08x}"
                    else: changed[index]['pixels'][0]^=1
                    matches,_=angle.match_profiles(self.manifest,changed if group=='scalar' else scalar,changed if group=='wrapper' else wrappers)
                    self.assertEqual(matches,[],(profile,group,index))
            for other in angle.PROFILES:
                if other!=profile:
                    self.assertEqual(angle.match_profiles(self.manifest,scalar,wrapper_rows(self.manifest,other))[0],[])

    def test_scalar_strict_missing_extra_reordered_duplicate_fields_types(self):
        rows=scalar_rows(self.manifest,angle.PROFILES[2])
        variants=[rows[:-1],rows+[rows[-1]],list(reversed(rows)),[rows[0]]+rows[:-1]]
        for field,value in [('id',1),('y',0),('x','3F800000'),('result',False),('result','nan'),('result',None),('extra',0)]:
            bad=copy.deepcopy(rows);bad[0][field]=value;variants.append(bad)
        for variant in variants:
            with self.assertRaises(ValueError): angle.strict_scalar('\n'.join(map(json.dumps,variant)),self.manifest['scalar_controls'])
        duplicate=json.dumps(rows[0]).replace('{','{"id":"duplicate",',1)
        with self.assertRaises(ValueError): angle.strict_scalar('\n'.join([duplicate]+list(map(json.dumps,rows[1:]))),self.manifest['scalar_controls'])
        with self.assertRaises(ValueError): angle.strict_scalar('\n'.join(map(json.dumps,rows))+'\n\n',self.manifest['scalar_controls'])

    def test_wrapper_strict_missing_extra_reordered_duplicate_fields_types(self):
        rows=wrapper_rows(self.manifest,angle.PROFILES[2]);variants=[rows[:-1],rows+[rows[-1]],list(reversed(rows)),[rows[0]]+rows[:-1]]
        for field,value in [('id',1),('width',True),('height',1.0),('pixels',[True]),('pixels',[-1]),('pixels',[2**32]),('pixels',[]),('pixels',{}),('extra',0)]:
            bad=copy.deepcopy(rows);bad[0][field]=value;variants.append(bad)
        for variant in variants:
            with self.assertRaises(ValueError):angle.strict_wrappers('\n'.join(map(json.dumps,variant)),self.cases,conformance.parse_output)
        with self.assertRaises(ValueError):angle.strict_wrappers('\n'.join(map(json.dumps,rows)),self.cases,lambda *_:[])
        duplicate=json.dumps(rows[0]).replace('{','{"pixels":[0],',1)
        with self.assertRaises(ValueError):angle.strict_wrappers('\n'.join([duplicate]+list(map(json.dumps,rows[1:]))),self.cases,conformance.parse_output)

    def test_frozen_intermediates_preserve_zero_and_uncontracted_semantics(self):
        rows=self.manifest['wrapper_controls']
        contraction=next(r for r in rows if r['id']=='v2-uncontracted-cancellation')
        self.assertEqual(contraction['atan2_inputs'],['00000000','40000000'])
        self.assertEqual(contraction['intermediates'][-3:],[['det-p0','3f800000'],['det-p1','3f800000'],['det','00000000']])
        negative_axis=next(r for r in rows if r['id']=='v2-negative-axis-core-a-scale-plus0-negative-y-negative-x')
        self.assertEqual(negative_axis['atan2_inputs'],['00000000','c0000000'])
        self.assertEqual(negative_axis['expected']['Apple2007AngleRn'],'40490fda')
        origins=[r for r in rows if r['api']=='Vector3Angle' and '-origin-' in r['id']]
        self.assertEqual(len(origins),4)
        self.assertTrue(all(r['atan2_inputs']==['00000000','00000000'] for r in origins))

    def test_fixture_mutation_does_not_change_controls_or_hash(self):
        before=(angle.sha256(angle.MANIFEST),angle.canonical_json(angle.control_document(self.manifest)))
        fixtures=json.loads((angle.ROOT/'tests/fixtures/images.json').read_text());fixtures.clear()
        with patch.object(Path,'read_text',side_effect=AssertionError('Controls must not read fixture files')):
            document=angle.control_document(self.manifest)
        self.assertEqual(before[1],angle.canonical_json(document))
        self.assertEqual(before[0],angle.sha256(angle.MANIFEST))

    def test_manifest_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'manifest.json';path.write_bytes(angle.MANIFEST.read_bytes()+b' ')
            with self.assertRaisesRegex(ValueError,'manifest drift'):angle.load_manifest(path)

    def test_mirror_strict_order_type_and_word(self):
        rows=[dict(id=r['id'],words=[v for _,v in r['intermediates']]) for r in self.manifest['wrapper_controls']]
        self.assertEqual(angle.strict_mirror('\n'.join(map(json.dumps,rows)),self.manifest['wrapper_controls']),rows)
        for modify in (lambda r:r.reverse(),lambda r:r[0]['words'].reverse(),lambda r:r[0].update(words=[0]),lambda r:r.append(r[-1])):
            bad=copy.deepcopy(rows);modify(bad)
            with self.assertRaises(ValueError):angle.strict_mirror('\n'.join(map(json.dumps,bad)),self.manifest['wrapper_controls'])


class AngleQualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.raylib=self.root/'raylib';(self.raylib/'src').mkdir(parents=True)
        self.manifest=angle.load_manifest()
        for name in self.manifest['raylib']['headers']:
            path=self.raylib/'src'/name;path.write_text('test '+name)
            self.manifest['raylib']['headers'][name]=angle.sha256(path)
        self.library=self.root/'raylib.a';self.library.write_text('static archive')
        self.libm=self.root/'libm.so.6';self.libm.write_text('runtime elf library')
        self.compiler=self.root/'clang';self.compiler.write_text('compiler image')
        self.work=self.root/'angle-reference';self.work.mkdir();self.report_path=self.work/'results.json'
        self.report_path.write_text(json.dumps(dict(qualified=True,selected_profile='stale')))
        self.profile='Glibc241AngleRn';self.failure=None;self.mutate=None;self.commands=[];self.states=[]
        self.outputs={};self.bad_meta=None;self.new_binary=True

    def runner(self,command,**kwargs):
        self.commands.append(command);self.states.append(json.loads(self.report_path.read_text()))
        label=Path(command[0]).name;out='';err=''
        if self.failure=='setup' and label=='git':raise RuntimeError('setup failed')
        if '--version' in command:out='mock clang 19.1.7\n'
        elif '-dumpmachine' in command:out='x86_64-test-linux-gnu\n'
        elif '-o' in command:
            binary=Path(command[command.index('-o')+1]);self.assertFalse(binary.exists())
            if self.failure=='compile':return subprocess.CompletedProcess(command,1,'','compile failed')
            if self.failure=='timeout':raise subprocess.TimeoutExpired(command,2,output='partial stdout',stderr='partial stderr')
            if self.new_binary:binary.write_text('fresh '+binary.name)
        elif label=='git':
            if 'rev-parse' in command:out=self.manifest['raylib']['revision']+'\n'
        elif label=='dpkg-query':out='base-files 1 amd64\n'
        elif label=='readelf':out='Build ID: 12345678abcdef00\n'
        elif label in ('pointer','pinned','canonical','intermediate-mirror','runtime-wrapper'):
            if self.failure=='run':return subprocess.CompletedProcess(command,1,'','run failed')
            initial=context(self.libm);final=context(self.libm,'final')
            if self.bad_meta:self.bad_meta(initial,final,label)
            err=json.dumps(initial)+'\n'+json.dumps(final)+'\n'
            if label in ('pointer','pinned'):
                rows=scalar_rows(self.manifest,'Glibc241AngleRn' if label=='pinned' else self.profile)
            elif label in ('canonical','runtime-wrapper'):rows=wrapper_rows(self.manifest,self.profile)
            else:rows=[dict(id=r['id'],words=[v for _,v in r['intermediates']]) for r in self.manifest['wrapper_controls']]
            out=self.outputs.get(label,'\n'.join(map(json.dumps,rows))+'\n')
            if self.mutate:self.mutate(label)
        else:raise AssertionError(command)
        return subprocess.CompletedProcess(command,0,out,err)

    def qualify(self,**kwargs):
        def which(name):return str(self.compiler) if name=='clang' else '/mock/bin/'+name
        with patch.object(angle,'load_manifest',return_value=copy.deepcopy(self.manifest)),patch.object(angle.shutil,'which',side_effect=which),patch.object(angle.platform,'system',return_value='Linux'),patch.object(angle.platform,'machine',return_value='x86_64'),patch.dict(angle.os.environ,{k:v for k,v in angle.os.environ.items() if k not in angle.LOADER_NAMES},clear=True):
            return angle.qualify(self.raylib,self.library,self.root,c_source=conformance.c_source,cases_from=conformance.cases_from,parse_output=conformance.parse_output,runner=self.runner,**kwargs)

    def failed(self):
        result=json.loads(self.report_path.read_text());self.assertFalse(result['qualified']);self.assertIsNone(result['selected_profile']);self.assertFalse(result['candidate_executed']);self.assertFalse(result['parity_established']);self.assertTrue(result['error']);return result

    def test_fresh_all_profiles_and_complete_evidence(self):
        for profile in angle.PROFILES:
            self.profile=profile
            result=self.qualify()
            self.assertTrue(result['qualified']);self.assertEqual(result['selected_profile'],profile)
            self.assertEqual(len(result['contexts']),5)
            self.assertEqual(len(result['observations']['runtime-pointer']),76)
            self.assertEqual(len(result['observations']['canonical-wrapper']),205)
            self.assertTrue(all(not state['qualified'] and state['selected_profile'] is None for state in self.states))
            self.assertEqual(result['package']['status'],'not-in-successful-dpkg-inventory')
            self.assertEqual((self.work/'canonical.c').read_text(),conformance.c_source(conformance.cases_from(angle.control_document(self.manifest))))

    def test_explicit_profile_cannot_bypass_qualification(self):
        for requested in ('Apple2007AngleRn','unknown'):
            with self.assertRaises(ValueError):self.qualify(requested_profile=requested)
            self.failed()
        self.outputs['pointer']='[]\n'
        with self.assertRaises(ValueError):self.qualify(requested_profile='Glibc241AngleRn')
        self.failed()

    def test_setup_compile_run_timeout_all_invalidate_stale_success(self):
        for failure in ('setup','compile','run','timeout'):
            self.failure=failure
            with self.assertRaises((RuntimeError,subprocess.TimeoutExpired)):self.qualify()
            result=self.failed();self.assertEqual(result['qualified'],False)
        self.assertEqual((self.work/'context-compile.stdout').read_text(),'partial stdout')
        self.assertEqual((self.work/'context-compile.stderr').read_text(),'partial stderr')

    def test_compile_success_without_new_binary_cannot_run_stale_file(self):
        for name in ('context.o','pointer','pinned','canonical'):(self.work/name).write_text('stale executable')
        self.new_binary=False
        with self.assertRaisesRegex(ValueError,'fresh nonempty'):self.qualify()
        self.failed();self.assertFalse((self.work/'context.o').exists())
        self.assertFalse(any(Path(c[0]).name in ('pointer','pinned','canonical') for c in self.commands))

    def test_wrong_rounding_ftz_daz_metadata_fail_before_future_generation(self):
        mutations=[('nearest',False),('rounding',1024),('control',8064|(1<<15)),('control',8064|(1<<6)),('control',8064|(1<<13)),('x87_control',895|(1<<10)),('binary32',False),('binary64',False),('eval_method',1),('endian','big'),('library_build_id',''),('libc_version','unknown'),('symbol','other')]
        for key,value in mutations:
            self.bad_meta=lambda initial,final,label,k=key,v=value:initial.update({k:v})
            generation=Mock()
            with self.assertRaises(ValueError):
                result=self.qualify();generation(result)
            generation.assert_not_called();self.failed()

    def test_missing_extra_duplicate_context_or_final_change_rejected(self):
        for change in (lambda i,f,l:i.pop('binary64'),lambda i,f,l:i.update(extra=1),lambda i,f,l:f.update(control=8064|(1<<15)),lambda i,f,l:i['loader_overrides'].update(LD_PRELOAD='anything')):
            self.bad_meta=change
            with self.assertRaises(ValueError):self.qualify()
            self.failed()
        initial=context(self.libm);final=context(self.libm,'final')
        with self.assertRaises(ValueError):angle.parse_context(json.dumps(initial)+'\n'+json.dumps(initial)+'\n'+json.dumps(final))
        with self.assertRaises(ValueError):angle.parse_context(json.dumps(initial).replace('{','{"kind":"initial-context",',1)+'\n'+json.dumps(final))

    def test_source_toolchain_and_artifact_drift_rejected(self):
        for target in (self.compiler,self.library,self.raylib/'src/raymath.h'):
            original=target.read_bytes()
            self.mutate=lambda label,p=target:p.write_bytes(original+b' drift') if label=='intermediate-mirror' else None
            with self.assertRaisesRegex(ValueError,'drift'):self.qualify()
            self.failed();target.write_bytes(original)
        self.mutate=None
        self.manifest['source_sha256']['toolchain.json']='0'*64
        with self.assertRaisesRegex(ValueError,'toolchain drift'):self.qualify()
        self.failed()

    def test_mixed_context_wrong_sign_and_pinned_source_mismatch_rejected(self):
        for label,rows in [('pointer',scalar_rows(self.manifest,'Sun239AngleRn')),('canonical',wrapper_rows(self.manifest,'Apple2007AngleRn')),('runtime-wrapper',wrapper_rows(self.manifest,'Sun239AngleRn')),('pinned',scalar_rows(self.manifest,'Apple2007AngleRn'))]:
            self.outputs={label:'\n'.join(map(json.dumps,rows))+'\n'}
            with self.assertRaises(ValueError):self.qualify()
            self.failed()
        rows=scalar_rows(self.manifest,'Glibc241AngleRn');rows[0]['result']='80000000'
        self.outputs={'pointer':'\n'.join(map(json.dumps,rows))+'\n'}
        with self.assertRaises(ValueError):self.qualify()
        self.failed()

    def test_library_path_stat_buildid_mismatch_rejected(self):
        for mutation in (lambda i,f,l:i['library_stat'].__setitem__(2,0),lambda i,f,l:(i.update(library_build_id='deadbeef'),f.update(library_build_id='deadbeef')),lambda i,f,l:(i.update(library_realpath=str(self.compiler)),f.update(library_realpath=str(self.compiler)))):
            self.bad_meta=mutation
            with self.assertRaises(ValueError):self.qualify()
            self.failed()

    def test_cross_process_control_drift_and_final_subprocess_drift(self):
        def mixed(initial,final,label):
            if label=='pointer':initial['x87_control']=final['x87_control']=639
        self.bad_meta=mixed
        with self.assertRaisesRegex(ValueError,'Mixed process'):self.qualify()
        self.failed();self.bad_meta=None;self.commands=[]
        original=self.runner
        def final_drift(command,**kwargs):
            result=original(command,**kwargs)
            if 'status' in command and any(Path(c[0]).name=='intermediate-mirror' for c in self.commands):
                self.compiler.write_text('changed during final subprocess')
            return result
        self.runner=final_drift
        with self.assertRaisesRegex(ValueError,'drift at acceptance'):self.qualify()
        self.failed()

    def test_invalid_cli_admission_invalidates_stale_report(self):
        import contextlib,io
        for args in (['--library','missing'],['--raylib-source','x','--library','y','--timeout','bad'],['--raylib-source','x','--library','y','--timeout','0']):
            self.report_path.write_text(json.dumps(dict(qualified=True,selected_profile='stale')))
            with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                angle.main(['--build-dir',str(self.root),*args])
            self.failed()

    def test_no_candidate_command_in_success_or_failure_paths(self):
        self.qualify()
        self.assertFalse(any('bun' in c[0] or any(str(a).endswith('.bend') for a in c) for c in self.commands))
        generation=Mock();self.failure='compile'
        with self.assertRaises(RuntimeError):
            result=self.qualify();generation(result)
        generation.assert_not_called()


if __name__=='__main__':unittest.main()
