const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../htdocs/luci-static/resources/view/wechatpush/client.js'), 'utf8');
let hintCalls = 0;
const hints = {'AA-BB-CC-DD-EE-FF': {name:'iQOO-15.lan',ipaddrs:['192.0.2.1']}};
const raw = [{mac:'aa:bb:cc:dd:ee:ff',ip:'192.0.2.1',name:'unknown',status:'unknown'}];
const client = new Function('view','rpc','fs','uci','L',source)(
    {extend: value=>value}, {declare: spec=>()=>{ if(spec.method==='getHostHints'){hintCalls++;return Promise.resolve(hints);} return Promise.resolve({}); }},
    {read:file=>Promise.resolve(file.endsWith('devices.json')?JSON.stringify({devices:raw}):'')},
    {get:()=> '0'}, {resolveDefault:(promise,fallback)=>promise.catch(()=>fallback)});
assert.equal(client.resolveDeviceNames(raw,'',hints)[0].name,'iQOO-15');
assert.equal(raw[0].name,'unknown');
assert.equal(client.resolveDeviceNames(raw,'aa:bb:cc:dd:ee:ff My alias.lan',hints)[0].name,'My alias.lan');
assert.equal(client.resolveDeviceNames(raw,'192.0.2.1 IP alias',hints)[0].name,'IP alias');
assert.equal(client.resolveDeviceNames(raw,'',{})[0].name,'未命名');
assert.equal(client.resolveDeviceNames([{name:'anonymous',mac:'unknown',ip:'192.0.2.1'}],'',hints)[0].name,'iQOO-15');
assert.equal(client.resolveDeviceNames([{name:'Known.lan',mac:'11:22:33:44:55:66',ip:'192.0.2.1'}],'',hints)[0].name,'Known');
client.fetchDevices().then(data=>{
    assert.equal(data.devices[0].name,'iQOO-15');
    assert.equal(data.devices[0].status,'unknown');
    assert.equal(hintCalls,1);
    console.log('PASS: original client list resolves aliases/QWRT names, strips automatic .lan, localizes placeholders without changing status');
}).catch(error=>{console.error(error);process.exitCode=1;});
