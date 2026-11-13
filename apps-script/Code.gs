/**
 * Quiz Live — ตัวส่งอีเมล (Google Apps Script Web app)
 *
 * ติดตั้งครั้งเดียว:
 *  1) เปิด https://script.new ด้วยบัญชีบริษัทที่จะใช้ส่ง → วางโค้ดทั้งไฟล์นี้แทนของเดิม → บันทึก (ตั้งชื่อ "Quiz Live Mailer")
 *  2) เลือกฟังก์ชัน setup แล้วกด "เรียกใช้" → อนุญาตสิทธิ์ → ดู "บันทึกการดำเนินการ" จะเห็นรหัสลับ (TOKEN)
 *  3) ทำให้ใช้งานได้ › การทำให้ใช้งานได้รายการใหม่ › ประเภท: เว็บแอป
 *       ดำเนินการในฐานะ: ฉัน · ผู้ที่มีสิทธิ์เข้าถึง: ทุกคน → ทำให้ใช้งานได้ → คัดลอก URL (ลงท้าย /exec)
 *  4) ใน Quiz Live › กล่อง ⚙ ผู้ดูแลระบบ › อีเมลระบบ → วาง URL และรหัสลับ → บันทึก → ส่งอีเมลทดสอบ
 *
 * ความปลอดภัย: รับเฉพาะคำขอที่มีรหัสลับตรงกับ Script Properties (TOKEN) · ส่งได้เฉพาะอีเมลโดเมน ALLOWED_DOMAIN
 * โควตา Google Workspace: ราว 1,500 ผู้รับต่อวัน
 */
var ALLOWED_DOMAIN = 'princgroup.com';

function setup() {
  var p = PropertiesService.getScriptProperties();
  var t = p.getProperty('TOKEN');
  if (!t) { t = Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '').slice(0, 8); p.setProperty('TOKEN', t); }
  MailApp.getRemainingDailyQuota(); // ขอสิทธิ์ส่งอีเมลตั้งแต่ตอนนี้
  Logger.log('รหัสลับ (TOKEN) สำหรับใส่ใน Quiz Live: ' + t);
  Logger.log('โควตาส่งอีเมลที่เหลือวันนี้: ' + MailApp.getRemainingDailyQuota());
}

function doPost(e) {
  var out = function (o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); };
  try {
    var d = JSON.parse(e.postData.contents);
    var token = PropertiesService.getScriptProperties().getProperty('TOKEN');
    if (!token || d.token !== token) return out({ ok: false, error: 'bad token' });
    var to = (d.to || []).map(function (x) { return String(x).trim().toLowerCase(); })
      .filter(function (x) { return x && x.slice(-(ALLOWED_DOMAIN.length + 1)) === '@' + ALLOWED_DOMAIN; });
    if (!to.length) return out({ ok: false, error: 'no recipients' });
    var tpl = MailTpl[d.kind];
    if (!tpl) return out({ ok: false, error: 'unknown kind' });
    var m = tpl(d);
    var opt = { to: to.join(','), subject: m.subject || d.subject, htmlBody: m.html, body: m.text, name: d.from_name || 'Quiz Live' };
    if (d.reply_to && /@/.test(d.reply_to)) opt.replyTo = d.reply_to;
    MailApp.sendEmail(opt);
    return out({ ok: true, sent: to.length, quota: MailApp.getRemainingDailyQuota() });
  } catch (err) {
    return out({ ok: false, error: String(err) });
  }
}

// ===== แม่แบบอีเมล Quiz Live (ใช้ร่วมกันทั้งหน้าเว็บและ Apps Script) =====
var MailTpl = (function () {
  var TH_M = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  var TH_D = ['อา.', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.'];
  function bkk(s) { var d = new Date(s); return new Date(d.getTime() + 7 * 3600e3); }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function dateTH(s, wd) { if (!s) return ''; var d = bkk(s); return (wd ? TH_D[d.getUTCDay()] + ' ' : '') + d.getUTCDate() + ' ' + TH_M[d.getUTCMonth()] + ' ' + String(d.getUTCFullYear() + 543).slice(2); }
  function timeTH(s) { if (!s) return ''; var d = bkk(s); return pad(d.getUTCHours()) + ':' + pad(d.getUTCMinutes()); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function link(site, hash) { return String(site || '').replace(/[#?].*$/, '').replace(/\/?$/, '/') + hash; }
  var LBL = 'color:#64748b;padding:3px 14px 3px 0;white-space:nowrap;vertical-align:top';
  function rows(list) { return '<table role="presentation" cellpadding="0" cellspacing="0" style="font-size:15px;margin:12px 0">' +
    list.filter(function (r) { return r[1]; }).map(function (r) { return '<tr><td style="' + LBL + '">' + esc(r[0]) + '</td><td>' + r[1] + '</td></tr>'; }).join('') + '</table>'; }
  function btn(href, text) { return '<a href="' + esc(href) + '" style="display:inline-block;background:#2563eb;color:#ffffff;text-decoration:none;font-weight:700;padding:12px 26px;border-radius:8px;font-size:16px">' + esc(text) + '</a>'; }
  function tag(t, kind) { var c = { pre: ['#e3efff', '#1f5ea8'], post: ['#fff1d6', '#8a5a00'], warn: ['#fde8e8', '#a32020'], late: ['#f3e8ff', '#6b21a8'] }[kind] || ['#e9eef3', '#475569'];
    return '<span style="background:' + c[0] + ';color:' + c[1] + ';border-radius:99px;padding:2px 10px;font-size:13px;font-weight:600;white-space:nowrap">' + esc(t) + '</span>'; }
  function shell(bar, body, foot) {
    return '<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>' +
      '<body style="margin:0;background:#eef2f7;font-family:Sarabun,\'Leelawadee UI\',Tahoma,Arial,sans-serif;color:#1e293b">' +
      '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eef2f7"><tr><td align="center" style="padding:20px 12px">' +
      '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden">' +
      '<tr><td style="background:#1e3a8a;color:#ffffff;padding:14px 22px;font-size:15px;font-weight:700">' + esc(bar) + '</td></tr>' +
      '<tr><td style="padding:22px;font-size:15px;line-height:1.6">' + body + '</td></tr>' +
      '<tr><td style="border-top:1px solid #e2e8f0;padding:14px 22px;font-size:12.5px;color:#64748b">' + foot + '</td></tr>' +
      '</table></td></tr></table></body></html>';
  }
  function roundsLine(c) { var r = c.rounds || []; if (!r.length) return '';
    var days = []; r.forEach(function (x) { var d = dateTH(x.starts_at, true); if (d && days.indexOf(d) < 0) days.push(d); });
    return esc((days.length ? days.join(', ') + ' · ' : '') + r.length + ' รอบ' + (r.length <= 4 ? ' (' + r.map(function (x) { return x.label; }).join(' / ') + ')' : '')); }
  function roundWhen(c, label) { var r = (c.rounds || []).filter(function (x) { return x.label === label; })[0];
    return r && r.starts_at ? ' · ' + dateTH(r.starts_at, true) + ' ' + timeTH(r.starts_at) + (r.ends_at ? '–' + timeTH(r.ends_at) : '') + ' น.' : ''; }
  function seatsBox(c, label) { var r = (c.rounds || []).filter(function (x) { return x.label === label; })[0]; if (!r) return '';
    return '<div style="background:#f1f5f9;border-radius:10px;padding:10px 14px;margin:0 0 16px;font-size:14px">' + esc(label) + ' จองแล้ว <b>' + r.booked + (r.seats ? ' / ' + r.seats : '') + '</b>' + (r.seats ? ' ที่นั่ง' : ' คน') + ' · ทั้งงาน ' + c.booked + ' คน</div>'; }
  var ACT = { 'จอง': 'pre', 'ย้ายรอบ': 'post', 'ยกเลิกจอง': 'warn', 'ลงชื่อย้อนหลัง': 'late', 'เพิ่มรายชื่อ': 'pre', 'เอาออกจากรายชื่อ': 'warn' };
  function by(e) { var d = e.detail || {}; return d.by === 'admin' ? 'ผู้จัดเพิ่มให้ (' + e.actor + ')' : d.by === 'sheet' ? 'ระบบเดิม' : /@/.test(e.actor || '') ? 'ผู้จัด (' + e.actor + ')' : 'ทำเองผ่าน QR'; }

  return {
    // คำเชิญผู้จัดร่วม
    invite: function (d) {
      var c = d.course || {}, url = link(d.site, '#course/' + c.id);
      var body = '<div style="font-size:21px;font-weight:700;margin-bottom:8px">คุณได้รับเชิญเป็นผู้จัดร่วม</div>' +
        '<div><b>' + esc(d.inviter_name) + '</b> (' + esc(d.inviter_email) + ') เพิ่มคุณเป็นผู้จัดร่วมของงานอบรมนี้</div>' +
        rows([['งานอบรม', '<b>' + esc(c.title) + '</b>'], ['วันที่', roundsLine(c)], ['สถานที่', esc(c.location || '')], ['เจ้าของงาน', esc(c.owner_email)]]) +
        btn(url, 'เปิดงานอบรม') +
        '<div style="background:#f1f5f9;border-radius:10px;padding:12px 16px;margin:18px 0;font-size:14px"><b>เข้าระบบครั้งแรก</b><ol style="margin:4px 0 0;padding-left:20px">' +
        '<li>กดปุ่ม “เปิดงานอบรม” หรือเข้า ' + esc(String(d.site || '').replace(/^https?:\/\//, '').replace(/\/$/, '')) + '</li>' +
        '<li>กด “เข้าสู่ระบบด้วย Google” แล้วเลือกอีเมล <b>' + esc(d.to_email || '') + '</b></li>' +
        '<li>งานนี้จะอยู่ในหน้าแรก หัวข้อ “งานอบรม”</li></ol></div>' +
        '<b>สิ่งที่ผู้จัดร่วมทำได้</b><ul style="margin:4px 0 0;padding-left:20px;font-size:14px">' +
        '<li>เปิด-ปิดรับจอง ลงชื่อ Pre/Post ของทุกรุ่น</li><li>เพิ่ม/แก้ผู้เข้าร่วม ย้ายรอบ สร้างลิงก์ลงชื่อย้อนหลัง</li>' +
        '<li>ดูรายงาน พิมพ์ใบลงชื่อ ส่งออก Excel · แก้ตั้งค่างาน</li></ul>' +
        '<div style="font-size:13px;color:#64748b;margin-top:6px">ลบงานอบรมไม่ได้ (เฉพาะเจ้าของงาน) · การแก้ไขทุกอย่างบันทึกในแท็บ “ประวัติ”</div>';
      return { subject: '[Quiz Live] คุณได้รับเชิญเป็นผู้จัดร่วม · ' + c.title,
        html: shell('Quiz Live · ระบบงานอบรม', body, 'ถ้าไม่ได้คาดว่าจะได้รับเมลนี้ ตอบกลับเพื่อแจ้งผู้เชิญได้ · อีเมลนี้ส่งจาก Quiz Live'),
        text: d.inviter_name + ' (' + d.inviter_email + ') เพิ่มคุณเป็นผู้จัดร่วมของงานอบรม "' + c.title + '"\nเปิดงาน: ' + url +
          '\nเข้าสู่ระบบด้วย Google โดยใช้อีเมล ' + (d.to_email || '') + '\n' };
    },
    // แจ้งทันที 1 เหตุการณ์
    event: function (d) {
      var c = d.course || {}, e = d.event || {}, x = e.detail || {}, url = link(d.site, '#course/' + c.id + ':people');
      var head = { 'จอง': 'มีผู้จองใหม่', 'ย้ายรอบ': 'มีผู้ย้ายรอบ', 'ยกเลิกจอง': 'มีผู้ยกเลิกการจอง', 'ลงชื่อย้อนหลัง': 'มีผู้ลงชื่อย้อนหลัง' }[e.action] || e.action;
      var round = x.to || x.from || '';
      var body = '<div style="font-size:21px;font-weight:700;margin-bottom:4px">' + esc(head) + '</div>' +
        rows([['ชื่อ-สกุล', '<b>' + esc(x.name) + '</b>'], ['รหัส', esc(x.emp_id)],
              ['รอบ', x.from && x.to ? esc(x.from) + ' → <b>' + esc(x.to) + '</b>' : '<b>' + esc(round) + '</b>' + esc(roundWhen(c, round))],
              ['ช่องทาง', tag(by(e), ACT[e.action])], ['เวลา', esc(dateTH(e.at) + ' ' + timeTH(e.at) + ' น.')]]) +
        seatsBox(c, x.to || x.from) + btn(url, 'เปิดรายชื่อผู้เข้าร่วม');
      return { subject: d.subject, html: shell('Quiz Live · แจ้งเตือนงานอบรม · ' + c.title, body,
        'ส่งถึงเจ้าของงานและผู้จัดร่วม · เปลี่ยนเป็นสรุปรายวันหรือปิดได้ที่ งานอบรม › ตั้งค่า › การแจ้งเตือนทางอีเมล'),
        text: head + ': ' + (x.name || '') + ' ' + (x.from && x.to ? x.from + ' → ' + x.to : round) + '\n' + url + '\n' };
    },
    // สรุปรายวัน
    digest: function (d) {
      var c = d.course || {}, it = d.items || [], url = link(d.site, '#course/' + c.id + ':people');
      function n(a) { return it.filter(function (x) { return x.action === a; }).length; }
      function tile(v, t, bg, fg) { return '<td width="33%" style="padding:4px"><div style="background:' + bg + ';border-radius:10px;padding:8px;text-align:center"><div style="font-size:24px;font-weight:700;color:' + fg + '">' + v + '</div><div style="font-size:13px;color:#475569">' + t + '</div></div></td>'; }
      var rs = (c.rounds || []).map(function (r) { return '<tr><td style="padding:5px 4px;border-bottom:1px solid #f1f5f9">' + esc(r.label) + (r.starts_at ? ' <span style="color:#64748b">· ' + esc(dateTH(r.starts_at)) + '</span>' : '') +
        '</td><td align="right" style="padding:5px 4px;border-bottom:1px solid #f1f5f9;white-space:nowrap">' + r.booked + (r.seats ? ' / ' + r.seats : '') + '</td></tr>'; }).join('');
      var shown = it.slice(-30).reverse();
      var list = shown.map(function (e) { var x = e.detail || {};
        return '<tr><td width="44" style="padding:6px 4px;border-bottom:1px solid #f1f5f9;white-space:nowrap;vertical-align:top;color:#64748b">' + esc(timeTH(e.at)) + '</td>' +
          '<td width="1%" style="padding:6px 8px 6px 4px;border-bottom:1px solid #f1f5f9;vertical-align:top;white-space:nowrap">' + tag(e.action, ACT[e.action]) + '</td>' +
          '<td style="padding:6px 4px;border-bottom:1px solid #f1f5f9">' + esc(x.name || x.key || '') + (x.dept ? ' · ' + esc(x.dept) : '') +
          '<br><span style="font-size:13px;color:#64748b">' + esc(x.from && x.to ? x.from + ' → ' + x.to : x.to || x.from || '') + '</span></td></tr>'; }).join('');
      var body = '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>' +
        tile('+' + n('จอง'), 'จองใหม่', '#e3efff', '#1e3a8a') + tile(n('ย้ายรอบ'), 'ย้ายรอบ', '#fff1d6', '#8a5a00') + tile(n('ยกเลิกจอง'), 'ยกเลิก', '#fde8e8', '#a32020') + '</tr></table>' +
        (rs ? '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;margin:14px 0"><tr><td style="color:#64748b;font-weight:600;padding:4px;border-bottom:1px solid #e2e8f0">รอบ</td><td align="right" style="color:#64748b;font-weight:600;padding:4px;border-bottom:1px solid #e2e8f0">จองแล้ว</td></tr>' + rs + '</table>' : '') +
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;margin:0 0 16px">' + list +
        (it.length > shown.length ? '<tr><td colspan="3" style="padding:6px 4px;color:#64748b">… และอีก ' + (it.length - shown.length) + ' รายการ (ดูทั้งหมดในระบบ แท็บประวัติ)</td></tr>' : '') + '</table>' +
        btn(url, 'เปิดงานอบรม');
      return { subject: d.subject, html: shell('Quiz Live · สรุปงานอบรม · ' + c.title, body,
        'ส่งเฉพาะวันที่มีความเคลื่อนไหว · ส่งถึงเจ้าของงานและผู้จัดร่วม · ตั้งค่าได้ที่ งานอบรม › ตั้งค่า › การแจ้งเตือนทางอีเมล'),
        text: 'สรุป ' + c.title + ': จองใหม่ ' + n('จอง') + ' ย้าย ' + n('ย้ายรอบ') + ' ยกเลิก ' + n('ยกเลิกจอง') + '\n' + url + '\n' };
    },
    test: function (d) {
      return { subject: d.subject || '[Quiz Live] ทดสอบการส่งอีเมล', html: shell('Quiz Live', '<div style="font-size:20px;font-weight:700">ส่งอีเมลได้แล้ว ✓</div><p>ระบบอีเมลของ Quiz Live เชื่อมกับ Apps Script เรียบร้อย</p>', 'อีเมลทดสอบจาก Quiz Live'),
        text: 'ระบบอีเมลของ Quiz Live เชื่อมกับ Apps Script เรียบร้อย' };
    }
  };
})();
