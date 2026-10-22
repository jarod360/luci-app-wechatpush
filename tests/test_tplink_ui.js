// Run with node tests/test_tplink_ui.js. No LuCI server or credentials needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
function E(tag, attrs, children) {
    if (children === undefined && (typeof attrs === 'string' || Array.isArray(attrs))) {
        children = attrs; attrs = {};
    }
    return { tag, attrs: attrs || {}, children, value: attrs && attrs.value || '', textContent: '', appendChild(child) { if (!Array.isArray(this.children)) this.children=[]; this.children.push(child); return child; } };
}
const options = {};
const section = { taboption(tab, type, key) {
    const field = { value: '', default: '', depends() {},
        formvalue() { return this.value; }, cfgvalue() { return ''; },
        getUIElement() { return { setValue: value => { this.value = value; } }; } };
    options[key] = field; return field;
} };
let modal, closed = 0;
const ui = { showModal(title, body) { modal = body; }, hideModal() { closed++; } };
const config = fs.readFileSync(path.join(root, 'htdocs/luci-static/resources/view/wechatpush/config.js'), 'utf8');
const block = config.slice(config.indexOf('var configView ='), config.indexOf("o = s.taboption('basic', form.Flag, 'prefer_client_page'"));
let applied = 0;
new Function('s','form','m','ui','E', block).call({handleSaveApply() { applied++; return Promise.resolve(); }},section, {Flag:0,Value:1}, {checkDepends() {}}, ui, E);
const flag = options.tplink_enable;
assert.equal(flag.default, '0');
assert.equal(options.tplink_password.password, true);
flag.onchange(null, 'config', '0');
assert.equal(modal, undefined);
flag.onchange(null, 'config', '1');
const inputs = modal.slice(0,3).map(row => row.children[2]);
const buttons = modal[5].children;
buttons[2].attrs.click(); // Empty username/password must not be accepted.
assert.equal(closed, 0);
assert.equal(applied, 0);
assert.ok(modal[4].textContent);
inputs[0].value = '192.168.0.1'; inputs[1].value = 'admin'; inputs[2].value = "a'b$()`\"";
buttons[2].attrs.click();
assert.equal(closed, 1);
assert.equal(applied, 1);
assert.equal(options.tplink_password.value, inputs[2].value);
flag.value = '1';
flag.onchange(null, 'config', '1');
modal[5].children[0].attrs.click();
assert.equal(flag.value, '0');

let enabled = false, reads = 0, cacheData = {}, aliasData = '', hostHints = {}, localDevices = {}, deferred;
const badgeSource = fs.readFileSync(path.join(root, 'htdocs/luci-static/resources/wechatpush/tplink.js'), 'utf8');
const helper = new Function('baseclass','fs','uci','L','E','ui','rpc', badgeSource)(
    {extend: value => value}, {read(file) { reads++; if (file.endsWith('device_aliases.list')) return Promise.resolve(aliasData); if (file.endsWith('/devices.json')) return Promise.resolve(JSON.stringify(localDevices)); return deferred ? new Promise(resolve => { deferred.resolve=resolve; }) : Promise.resolve(JSON.stringify(cacheData)); }},
    {get() { return enabled ? '1' : '0'; }}, {resolveDefault: (promise, fallback) => promise.catch(() => fallback)}, E, ui, {declare: () => () => Promise.resolve(hostHints)});
(async () => {
    assert.equal(await helper.read(), null);
    assert.equal(reads, 0);
    enabled = true; await helper.read(); assert.equal(reads, 1);
    const fresh = helper.badge({state:'connected',updated_at:Date.now()/1000,online:27,offline:24});
    assert.ok(fresh.attrs.style.includes('green'));
    assert.ok(fresh.children.includes('27'));
    const stale = helper.badge({state:'connected',updated_at:1});
    assert.ok(!stale.attrs.style.includes('green'));
    assert.ok(stale.children.includes('过期'));
    assert.equal(fresh.children, '无线客户端在线 27');
    const logFailure = helper.badge({state:'connected',updated_at:Date.now()/1000,logs_ok:false});
    assert.equal(logFailure.children, '离线（无线日志读取失败）');
    const offline = helper.badge({state:'authentication_failed'});
    assert.ok(offline.children.includes('用户名或密码错误'));
    assert.ok(offline.attrs.style.includes('color:red'));
    assert.ok(offline.children.startsWith('离线'));
    const unsupported = helper.badge({state:'invalid_response'});
    assert.ok(unsupported.children.includes('不适配您的TP-LINK设备，请联系ChatGPT协助开发。'));
    assert.ok(unsupported.attrs.style.includes('color:orange'));
    const waiting = helper.badge({state:'waiting'});
    assert.ok(waiting.children.includes('读取状态中'));
    assert.ok(!waiting.children.includes('离线'));
    assert.ok(!waiting.attrs.style.includes('color:red'));
    cacheData={state:'connected',updated_at:Date.now()/1000,online:3,online_clients:[
        {name:'anonymous',mac:'aa:bb:cc:dd:ee:ff',ip:'192.0.2.1',ap:'AP-A',ssid:'test'},
        {name:'anonymous',mac:'11:22:33:44:55:66',ip:'192.0.2.2',ap:'AP-B'},
        {name:'anonymous',mac:'22:33:44:55:66:77',ip:'192.0.2.3'},
        {name:'unknown',mac:'33:44:55:66:77:88',ip:'192.0.2.4'},
        {name:'unknown',mac:'44:55:66:77:88:99',ip:'192.0.2.5'}]};
    aliasData='192.0.2.1 IP fallback\nAA-BB-CC-DD-EE-FF 手机 100% "别名"\n192.0.2.2 IP alias\n';
    hostHints={'22:33:44:55:66:77':{name:'iQOO15.lan',ipaddrs:['192.0.2.3']}};
    localDevices={devices:[{mac:'33:44:55:66:77:88',ip:'192.0.2.4',name:'本机设备名'}]};
    await helper.showClients();
    const table=modal[2].children[0];
    assert.equal(table.children[1].children[0].children, '手机 100% "别名"');
    assert.equal(table.children[2].children[0].children, 'IP alias');
    assert.equal(table.children[3].children[0].children, 'iQOO15');
    assert.equal(table.children[4].children[0].children, '本机设备名');
    assert.equal(table.children[5].children[0].children, '未命名');
    assert.ok(modal[0].children.includes('@media(max-width:767px)'));
    deferred={};
    const pending=helper.showClients();
    const loading=modal;
    modal[1].children[0].attrs.click();
    deferred.resolve(JSON.stringify(cacheData));
    await pending;
    assert.equal(modal, loading, 'closed modal must not reopen after async reads');
    console.log('PASS: aliases, client details, responsive rules and cancellation');
    console.log('PASS: opt-in modal validation, save/cancel, credential characters, disabled reads and status freshness');
})().catch(error => { console.error(error); process.exitCode = 1; });
