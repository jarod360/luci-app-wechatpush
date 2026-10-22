"""Run with Python + lupa (Lua 5.1); no network or router credentials needed."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parents[1]


class TPLinkTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.api = self.lua.execute((ROOT / 'root/usr/share/wechatpush/tplink_api.lua').read_text(encoding='utf-8'))
        self.lua.globals().api = self.api

    def test_offline_requires_fresh_explicit_matching_mac(self):
        self.lua.execute('''
            local cache = {state='connected', updated_at=100, wireless={['aa:bb:cc:dd:ee:ff']=true}, clients={['aa:bb:cc:dd:ee:ff']='offline'}}
            assert(api.state(cache, 'AA-BB-CC-DD-EE-FF', 130) == 'offline')
            assert(api.state(cache, 'aa:bb:cc:dd:ee:ff', 131) == 'unknown')
            assert(api.state(cache, 'aa:bb:cc:dd:ee:ff', 99) == 'unknown')
            assert(api.state(cache, '11:22:33:44:55:66', 110) == 'unmanaged')
            assert(api.state(cache, nil, 110) == 'unmanaged')
            for _, state in ipairs({'request_failed','authentication_failed','invalid_response'}) do
                cache.state = state
                assert(api.state(cache, 'aa:bb:cc:dd:ee:ff', 110) == 'unknown')
            end
            assert(api.state(nil, 'aa:bb:cc:dd:ee:ff', 110) == 'unmanaged')
        ''')

    def test_wireless_scope_survives_stale_or_failed_cache(self):
        self.lua.execute("""
            local c={state='request_failed',updated_at=1,wireless={['aa:bb:cc:dd:ee:ff']=true},clients={}}
            assert(api.state(c,'aa:bb:cc:dd:ee:ff',100)=='unknown')
            assert(api.state(c,'11:22:33:44:55:66',100)=='unmanaged')
            local function request(path,b)
                if b.login then return {error_code=0,stok='abc'} end
                if b.host_management then return {error_code=0,host_management={host_info={
                    {h={mac='aa:bb:cc:dd:ee:ff',type='wired',state='offline'}},
                    {h={mac='11:22:33:44:55:66',type='wireless',state='online',hostname='%E6%89%8B%E6%9C%BA',ip='192.0.2.2',ap_name='AP-A',ssid='WiFi'}}}}} end
                return {error_code=0}
            end
            local d=api.collect(request,'u','p',c)
            assert(not d.wireless['aa:bb:cc:dd:ee:ff'])
            assert(d.online==1 and d.offline==0)
            assert(#d.online_clients==1 and d.online_clients[1].mac=='11:22:33:44:55:66')
            assert(d.online_clients[1].ap=='AP-A' and d.online_clients[1].name=='手机')
        """)

    def test_disconnect_window_requires_new_valid_observation(self):
        self.lua.execute("""
            local m='aa:bb:cc:dd:ee:ff'
            local c={state='connected',updated_at=129,wireless={[m]=true},clients={[m]='offline'},offline_since={[m]=100}}
            assert(api.ready(c,m,129)=='pending')
            assert(api.ready(c,m,130)=='pending') -- observation predates deadline
            c.updated_at=130
            assert(api.ready(c,m,130)=='offline')
            assert(api.ready(c,m,161)=='unknown')
            c.state='request_failed';assert(api.ready(c,m,130)=='unknown')
            c.state='connected';c.clients[m]='online';assert(api.ready(c,m,130)=='online')
            c.clients[m]=nil;assert(api.ready(c,m,130)=='unknown')
            c.clients[m]='offline';c.offline_since={};assert(api.ready(c,m,130)=='pending')
        """)

    def test_log_failure_and_same_second_recovery_are_conservative(self):
        self.lua.execute("""
            local m='76:b6:e9:9f:86:25'
            local now=os.time({year=2026,month=10,day=22,hour=18,min=45,sec=0})
            for _, reverse in ipairs({false,true}) do
                local function request(path,b)
                    if b.login then return {error_code=0,stok='abc'} end
                    if b.host_management then return {error_code=0,host_management={host_info={}}} end
                    if b.system.read_logs then
                        local rows={{a='<1>2026-10-22 18:40:00[WSTATION]STA(MAC 76-B6-E9-9F-86-25)断开连接。'},
                            {a='<1>2026-10-22 18:40:00[WSTATION]STA(MAC 76-B6-E9-9F-86-25)成功漫游到AP test'}}
                        if reverse then rows[1],rows[2]=rows[2],rows[1] end
                        return {error_code=0,syslog=rows,total=2}
                    end
                    return {error_code=0}
                end
                local d=api.collect(request,'u','p',nil,now);d.updated_at=now
                assert(d.station_events[m].state=='online')
                assert(api.ready(d,m,now)=='unknown')
            end
            local c={state='connected',updated_at=now,wireless={[m]=true},clients={[m]='offline'},logs_ok=false,offline_since={[m]=now-100}}
            assert(api.ready(c,m,now)=='unknown')
        """)

    def test_old_disconnect_cannot_override_newer_online_observation(self):
        self.lua.execute("""
            local m='76:b6:e9:9f:86:25'
            local now=os.time({year=2026,month=10,day=22,hour=18,min=45,sec=0})
            local previous={updated_at=now-10,clients={[m]='online'},wireless={[m]=true}}
            local function request(path,b)
                if b.login then return {error_code=0,stok='abc'} end
                if b.host_management then return {error_code=0,host_management={host_info={}}} end
                if b.system.read_logs then return {error_code=0,syslog={{a='<1>2026-10-22 18:40:00[WSTATION]STA(MAC 76-B6-E9-9F-86-25)断开连接。'}},total=1} end
                return {error_code=0}
            end
            local d=api.collect(request,'u','p',previous,now);d.updated_at=now
            assert(api.ready(d,m,now)=='unknown')
        """)

    def test_protocol_and_conflicting_states(self):
        self.lua.execute('''
            local calls = 0
            local function request(path, body)
                calls = calls + 1
                if calls == 1 then
                    assert(path == '/' and body.login.username == 'admin')
                    assert(body.login.password == api.encode('password'))
                    return {error_code=0, stok='abcdef1234'}
                elseif calls == 2 then
                    assert(path == '/stok=abcdef1234/ds' and body.method == 'get')
                    assert(body.host_management.table[1] == 'host_info')
                    return {error_code=0, host_management={host_info={
                        {host_1={mac='AA-BB-CC-DD-EE-FF',state='offline',type='wireless'}},
                        {host_2={mac='aa:bb:cc:dd:ee:ff',state='online',type='wireless'}},
                        {host_3={mac='11:22:33:44:55:66',state='offline',type='wireless'}},
                        {host_4={mac='22:33:44:55:66:77',type='wireless'}},
                        {host_5={mac='invalid',state='offline',type='wireless'}}
                    }}}
                end
                assert(body.method == 'do' and body.system ~= nil)
                return {error_code=0}
            end
            local data = api.collect(request, 'admin', 'password')
            assert(calls == 3 and data.online == 1 and data.offline == 1)
            assert(data.clients['aa:bb:cc:dd:ee:ff'] == 'online')
            assert(data.clients['22:33:44:55:66:77'] == 'unknown')
        ''')

    def test_failures_logout_without_false_offline(self):
        self.lua.execute('''
            for _, mode in ipairs({'throw','malformed','error_code'}) do
                local calls = 0
                local function request(path, body)
                    calls = calls + 1
                    if calls == 1 then return {error_code=0,stok='abc123'} end
                    if calls == 3 then return {error_code=0} end
                    if mode == 'throw' then error('network') end
                    if mode == 'error_code' then return {error_code=-1} end
                    return {error_code=0,host_management={host_info='bad'}}
                end
                assert(not pcall(api.collect, request, 'admin', 'password'))
                assert(calls == 3)
            end
            local calls = 0
            assert(not pcall(api.collect, function() calls=calls+1; return {error_code=-1} end, 'a','b'))
            assert(calls == 1)
        ''')

    def test_helper_lua51_syntax(self):
        source = (ROOT / 'root/usr/share/wechatpush/tplink.lua').read_text(encoding='utf-8')
        self.lua.eval('function(s) return assert(loadstring(s)) end')('\n'.join(source.splitlines()[1:]))

    def test_recent_offline_counts_current_state_and_24h_boundary(self):
        self.lua.execute('''
            local now = 200000
            local data = {clients={a='offline',b='offline',c='offline',d='offline',e='online',f='offline'}}
            local old = {clients={a='online'},offline_since={b=now-86400,c=now-86401,d=now+10}}
            api.recent_count(data,old,now,{e=now-10,f=now-60})
            assert(data.offline_24h == 3)
            assert(data.offline_since.a == now)
            assert(data.offline_since.b == now-86400)
            assert(data.offline_since.f == now-60)
            assert(not data.offline_since.c and not data.offline_since.d and not data.offline_since.e)
            -- Stable offline devices do not become newly offline on every poll.
            local next = {clients=data.clients}
            api.recent_count(next,data,now+1,nil)
            assert(next.offline_24h == 2 and next.offline_since.a == now)
        ''')

    def test_missing_client_requires_latest_explicit_disconnect(self):
        self.lua.execute('''
            local now = os.time({year=2026,month=10,day=22,hour=18,min=45,sec=0})
            for _, mode in ipairs({'disconnect','reconnect','present','logs_fail'}) do
                local function request(path, body)
                    if body.login then return {error_code=0,stok='abc123'} end
                    if body.host_management then
                        return {error_code=0,host_management={host_info=mode=='present' and {{h={mac='76-B6-E9-9F-86-25',state='online',type='wireless'}}} or {}}}
                    end
                    if body.system.read_logs then
                        if mode=='logs_fail' then error('network') end
                        local lines={{a='<1>2026-10-22 18:39:00[WSTATION]STA(MAC 76-B6-E9-9F-86-25)断开连接。'}}
                        if mode=='reconnect' then table.insert(lines,1,{b='<1>2026-10-22 18:40:00[WSTATION]STA(MAC 76-B6-E9-9F-86-25)成功连接到AP test'}) end
                        return {error_code=0,syslog=lines,total=#lines}
                    end
                    return {error_code=0}
                end
                local data = api.collect(request,'admin','password',{wireless={['76:b6:e9:9f:86:25']=true}},now)
                data.updated_at=now
                local state=api.state(data,'76:b6:e9:9f:86:25',now)
                if mode=='disconnect' then assert(state=='offline' and data.offline_24h==1)
                elseif mode=='present' then assert(state=='online')
                else assert(state=='unknown') end
            end
        ''')


if __name__ == '__main__':
    unittest.main()
