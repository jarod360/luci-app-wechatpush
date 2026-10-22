'use strict';
'require baseclass';
'require fs';
'require uci';
'require ui';
'require rpc';

return baseclass.extend({
	callHostHints: rpc.declare({ object: 'luci-rpc', method: 'getHostHints', expect: { '': {} } }),
	read: function () {
		if (uci.get('wechatpush', 'config', 'tplink_enable') !== '1')
			return Promise.resolve(null);
		return L.resolveDefault(fs.read('/tmp/wechatpush/tplink_status.json'), '').then(function (text) {
			try { return JSON.parse(text); } catch (e) { return { state: 'waiting' }; }
		});
	},
	showClients: function () {
		var self = this, requestId = this._clientRequest = (this._clientRequest || 0) + 1;
		var close = function () { self._clientRequest++; ui.hideModal(); };
		ui.showModal('TP-LINK 在线客户端', [E('p', '正在读取客户端列表…'), E('div', { 'class': 'right' }, [E('button', { 'type': 'button', 'class': 'btn', 'click': close }, '关闭')])]);
		return Promise.all([this.read(), L.resolveDefault(fs.read('/usr/share/wechatpush/api/device_aliases.list'), ''), L.resolveDefault(this.callHostHints(), {}), L.resolveDefault(fs.read('/tmp/wechatpush/devices.json'), '{}')]).then(function (result) {
			if (requestId !== self._clientRequest) return;
			var data = result[0], aliases = Object.create(null);
			String(result[1]).split(/\r?\n/).forEach(function (line) {
				var match = line.trim().match(/^(\S+)\s+(.+)$/);
				if (match && match[1].charAt(0) !== '#') {
					var key = match[1].toLowerCase().replace(/-/g, ':');
					if (!aliases[key]) aliases[key] = match[2].trim();
				}
			});
			var hostNames = Object.create(null), deviceNames = Object.create(null);
			var usefulName = function (value) {
				return typeof value === 'string' && value.trim() && !/^(anonymous|unknown|未命名|未知|\*)$/i.test(value.trim()) ? value.trim() : '';
			};
			var remember = function (map, mac, ips, name) {
				name = usefulName(name); if (!name) return;
				if (mac) map[String(mac).toLowerCase().replace(/-/g, ':')] = name;
				(Array.isArray(ips) ? ips : []).forEach(function (ip) { if (!map[ip]) map[ip] = name; });
			};
			Object.keys(result[2] || {}).forEach(function (mac) {
				var hint = result[2][mac] || {}; remember(hostNames, mac, hint.ipaddrs, hint.name || hint.hostname);
			});
			try {
				var localDevices = JSON.parse(result[3]).devices;
				(Array.isArray(localDevices) ? localDevices : []).forEach(function (row) { if (row) remember(deviceNames, row.mac, [row.ip], row.name); });
			} catch (e) {}
			var fresh = data && data.state === 'connected' && typeof data.updated_at === 'number' &&
				Date.now() / 1000 >= data.updated_at && Date.now() / 1000 - data.updated_at <= 30;
			var rows = data && Array.isArray(data.online_clients) ? data.online_clients.filter(function (row) { return row && typeof row === 'object'; }) : [];
			var table = E('table', { 'class': 'tplink-client-table', 'style': 'width:100%;border-collapse:collapse;font-size:13px' }, [E('tr', {},
				['设备名称', 'IP 地址', 'MAC 地址', '所属 AP', '无线网络（SSID）'].map(function (label) { return E('th', { 'style': 'text-align:left;padding:10px 8px;border-bottom:2px solid #ddd;white-space:nowrap' }, label); }))]);
			rows.forEach(function (row) {
				table.appendChild(E('tr', {}, ['name', 'ip', 'mac', 'ap', 'ssid'].map(function (key) {
					var value = typeof row[key] === 'string' && row[key] ? row[key] : '—';
					if (key === 'name') {
						var mac = String(row.mac || '').toLowerCase().replace(/-/g, ':');
						value = aliases[mac] || aliases[row.ip] || (hostNames[mac] || hostNames[row.ip] || deviceNames[mac] || deviceNames[row.ip] || usefulName(row.name)).replace(/\.lan$/i, '') || '未命名';
					}
					return E('td', { 'style': 'padding:10px 8px;border-bottom:1px solid #ddd' }, value);
				})));
			});
			ui.showModal('TP-LINK 在线客户端', [
				E('style', {}, '.modal.tplink-client-dialog{width:1100px!important;width:min(1100px,96vw)!important;max-width:96vw!important;box-sizing:border-box}.tplink-client-table td{white-space:nowrap}@media(max-width:767px){.modal.tplink-client-dialog{padding:14px!important}.tplink-client-table{table-layout:fixed}.tplink-client-table th:nth-child(3),.tplink-client-table td:nth-child(3),.tplink-client-table th:nth-child(5),.tplink-client-table td:nth-child(5){display:none}.tplink-client-table th:nth-child(1){width:29%}.tplink-client-table th:nth-child(2){width:32%}.tplink-client-table th:nth-child(4){width:39%}.tplink-client-table td{white-space:normal;overflow-wrap:anywhere}.tplink-client-table th,.tplink-client-table td{padding:9px 5px!important}}'),
				E('p', fresh ? '当前在线 ' + Number(data.online || 0) + ' 台；数据更新于 ' + new Date(data.updated_at * 1000).toLocaleString() : '当前检测数据不可用或已过期，以下如有记录仅供参考。'),
				E('div', { 'style': 'overflow-x:auto;max-height:60vh;overflow-y:auto' }, rows.length ? [table] : [E('p', fresh && data.online_clients ? '暂无在线无线客户端。' : '暂未取得客户端明细，请稍后刷新。')]),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn cbi-button', 'click': function () { return self.showClients(); } }, '刷新'), ' ',
					E('button', { 'class': 'btn cbi-button', 'click': close }, '关闭')])
			], 'tplink-client-dialog');
		});
	},
	badge: function (data) {
		if (!data) return E('span');
		var fresh = typeof data.updated_at === 'number' && Date.now() / 1000 >= data.updated_at && Date.now() / 1000 - data.updated_at <= 30;
		var connected = data.state === 'connected' && fresh && data.logs_ok !== false;
		var unsupported = data.state === 'invalid_response';
		var waiting = data.state === 'waiting';
		var text = waiting ? '读取状态中…' : connected ? '' : unsupported ? '不适配' : '离线';
		var color = waiting ? '#777' : connected ? 'green' : unsupported ? 'orange' : 'red';
		var detail = connected ? '无线客户端在线 ' + Number(data.online || 0) :
			unsupported ? ' 不适配您的TP-LINK设备，请联系ChatGPT协助开发。' :
			data.state === 'authentication_failed' ? '（用户名或密码错误）' :
			data.state === 'configuration_error' ? '（请填写管理地址、用户名和密码）' :
			data.state === 'connected' && data.logs_ok === false ? '（无线日志读取失败）' :
			data.state === 'connected' ? '（检测数据已过期）' :
			waiting ? '' : '（无法连接路由器）';
		return E(connected ? 'button' : 'span', { 'type': connected ? 'button' : null, 'title': connected ? '查看在线无线客户端明细' : null, 'click': connected ? this.showClients.bind(this) : null, 'style': 'display:inline-block;cursor:' + (connected ? 'pointer' : 'default') + ';padding:7px 12px;border:1px solid ' + color + ';border-radius:4px;font-size:13px;font-weight:700;line-height:1.5;background-color:' + color + ';color:#fff' }, text + detail);
	}
});
