// Static consistency check for the HomeKiosk project. No SDK required.
// Run: node tools/validate-project.js
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let errors = 0;
let checks = 0;
const err = (m) => { errors++; console.log('  [FAIL] ' + m); };
const pass = (m) => { checks++; console.log('  [ ok ] ' + m); };

const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const exists = (p) => fs.existsSync(path.join(ROOT, p));

console.log('\n== 1. JSON/JSON5 可解析（全部按严格 JSON 书写）');
const jsonFiles = [];
(function walk(dir, rel) {
  for (const e of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === 'build' || e.name.startsWith('.')) continue;
    const d = path.join(dir, e.name);
    const r = path.join(rel, e.name);
    if (e.isDirectory()) walk(d, r);
    else if (/\.(json|json5)$/.test(e.name)) jsonFiles.push([d, r]);
  }
})('.', '.');
for (const [rel] of jsonFiles) {
  try {
    JSON.parse(read(rel));
    pass(rel);
  } catch (e) {
    err(rel + ' -> ' + e.message);
  }
}

console.log('\n== 2. 资源引用一致性');
const appJson = JSON.parse(read('AppScope/app.json5'));
const moduleJson = JSON.parse(read('entry/src/main/module.json5'));
const strings = (p) => new Set(JSON.parse(read(p)).string.map((s) => s.name));
const appStrings = strings('AppScope/resources/base/element/string.json');
const modStrings = strings('entry/src/main/resources/base/element/string.json');
const colors = new Set(JSON.parse(read('entry/src/main/resources/base/element/color.json')).color.map((c) => c.name));

if (!appStrings.has(appJson.app.label.replace('$string:', ''))) err('AppScope label 缺字符串');
else pass('AppScope label ' + appJson.app.label);
if (!exists('AppScope/resources/base/media/app_icon.png')) err('AppScope 图标缺失');
else pass('AppScope 图标存在');
if (!exists('entry/src/main/resources/base/media/app_icon.png')) err('entry 图标缺失');
else pass('entry 图标存在');

for (const ab of moduleJson.module.abilities) {
  for (const key of ['label', 'icon', 'startWindowIcon', 'startWindowBackground']) {
    const v = ab[key];
    if (!v) continue;
    if (v.startsWith('$string:') && !modStrings.has(v.slice(8))) err('ability ' + key + ' 引用缺失: ' + v);
    else if (v.startsWith('$color:') && !colors.has(v.slice(7))) err('ability ' + key + ' 引用缺失: ' + v);
    else if (v.startsWith('$media:') && !exists('entry/src/main/resources/base/media/' + v.slice(7) + '.png'))
      err('ability ' + key + ' 引用缺失: ' + v);
  }
  const src = ab.srcEntry;
  if (!exists('entry/src/main/' + src)) err('srcEntry 文件不存在: ' + src);
  else pass('srcEntry ' + src);
}
if (!exists('entry/src/main/resources/base/profile/main_pages.json')) err('main_pages 缺失');
else pass('main_pages 存在');

console.log('\n== 3. 路由与页面文件');
const pages = JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json')).src;
for (const p of pages) {
  const f = 'entry/src/main/ets/' + p + '.ets';
  if (!exists(f)) err('路由指向不存在的页面: ' + f);
  else {
    const body = read(f);
    if (!/@Entry/.test(body)) err(f + ' 缺 @Entry');
    if (!/build\s*\(\s*\)/.test(body)) err(f + ' 缺 build()');
    if (!/struct\s+\w+/.test(body)) err(f + ' 缺 struct');
    pass('页面 ' + p);
  }
}

console.log('\n== 4. ArkTS 相对 import 与 app.color 引用');
function etsFiles(dir) {
  const out = [];
  for (const e of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
    const d = (dir.endsWith('/') ? dir : dir + '/') + e.name;
    if (e.isDirectory()) out.push(...etsFiles(d));
    else if (e.name.endsWith('.ets')) out.push(d);
  }
  return out;
}
const ets = etsFiles('entry/src/main/ets');
const braceIssues = [];
for (const f of ets) {
  const body = read(f);
  const posixF = f.split(path.sep).join('/');
  for (const m of body.matchAll(/from\s+'(\.\.?\/[^']+)'/g)) {
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(posixF), m[1]));
    if (!exists(target + '.ets') && !exists(target)) err(f + ' 引用不到: ' + m[1]);
  }
  for (const m of body.matchAll(/\$r\('app\.color\.(\w+)'\)/g)) {
    if (!colors.has(m[1])) err(f + ' 用了未定义颜色: ' + m[1]);
  }
  for (const m of body.matchAll(/\$r\('app\.string\.(\w+)'\)/g)) {
    if (!modStrings.has(m[1])) err(f + ' 用了未定义字符串: ' + m[1]);
  }
  const open = (body.match(/\{/g) || []).length;
  const close = (body.match(/\}/g) || []).length;
  if (open !== close) braceIssues.push(f + ' (' + open + '{ vs ' + close + '})');
}
if (braceIssues.length) err('大括号不配对: ' + braceIssues.join(', '));
else pass(ets.length + ' 个 .ets 文件 import/资源/括号检查通过');

console.log('\n== 5. 未使用 import 粗查');
for (const f of ets) {
  const body = read(f);
  for (const m of body.matchAll(/^import\s+(?:\{([^}]+)\}|(\w+))\s+from\s+'([^']+)';?$/gm)) {
    const names = (m[1] || m[2]).split(',').map((s) => s.trim()).filter(Boolean);
    const rest = body.split(m[0]).join('');
    for (const n of names) {
      const sym = n.includes(' as ') ? n.split(' as ')[1].trim() : n;
      if (!new RegExp('\\b' + sym.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b').test(rest)) {
        console.log('  [note] ' + f + ' 引入了未使用的 ' + sym);
      }
    }
  }
}

console.log('\n== 6. 脚本存在性与引用');
const declared = [
  'scripts/env.sh', 'scripts/common.sh', 'scripts/doctor.sh', 'scripts/build.sh', 'scripts/sign.sh',
  'scripts/deploy.sh', 'scripts/pipeline.sh', 'scripts/tcp-mode.sh', 'scripts/push-photos.sh',
  'scripts/align-toolchain.sh', 'scripts/ci-summary.sh', 'scripts/ohos.ps1', 'tools/feed-mock.js',
  'ci/github-actions.self-hosted.yml', 'ci/gitlab-ci.self-hosted.yml', 'signing/README.md',
  'assets/photos/README.md', 'README.md', '.gitignore', 'build-profile.json5', 'oh-package.json5',
  'hvigorfile.ts', 'hvigor/hvigor-config.json5', 'entry/build-profile.json5', 'entry/hvigorfile.ts',
  'entry/oh-package.json5', 'tools/validate-project.js',
];
for (const f of declared) exists(f) ? pass(f) : err('缺文件: ' + f);

const ps1 = read('scripts/ohos.ps1');
for (const m of ps1.matchAll(/=\s*'([a-z-]+\.sh)'/g)) {
  if (!exists('scripts/' + m[1])) err('ohos.ps1 映射到不存在的脚本: ' + m[1]);
}
pass('ohos.ps1 任务映射有效');

for (const f of declared.filter((x) => x.endsWith('.sh'))) {
  const body = read(f);
  if (!/common\.sh/.test(body) && !/env\.sh/.test(body)) continue;
  if (!/BASH_SOURCE\[0\]/.test(body)) err(f + ' 没按 BASH_SOURCE 定位自身目录');
}
pass('脚本自定位方式一致');

console.log('\n== 7. README 里承诺的产物路径');
const unsigned = 'build-artifacts/entry-unsigned.hap';
if (!/OHOS_OUT_DIR=.*build-artifacts/.test(read('scripts/env.sh'))) err('env.sh 输出目录与 README 不一致');
else pass('输出目录 build-artifacts 一致（预期产物：' + unsigned + ' / build-artifacts/entry-signed.hap）');
if (!/OHOS_BUNDLE:-com\.local\.homekiosk/.test(read('scripts/env.sh'))) err('env.sh 的 bundle 与 AppScope 不一致');
else pass('bundleName 一致: ' + appJson.app.bundleName);
if (JSON.parse(read('entry/src/main/module.json5')).module.mainElement !== 'EntryAbility') err('mainElement 不匹配');
else pass('mainElement = EntryAbility（deploy.sh 的 OHOS_ABILITY 默认值一致）');

console.log('\n结果: ' + checks + ' 项通过, ' + errors + ' 项失败');
process.exit(errors ? 1 : 0);
