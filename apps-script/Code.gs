/**
 * Quiz Live PLPN — ตัวส่งอีเมล (Google Apps Script Web app)
 *
 * ติดตั้งครั้งเดียว:
 *  1) เปิด https://script.new ด้วยบัญชีบริษัทที่จะใช้ส่ง → วางโค้ดทั้งไฟล์นี้แทนของเดิม → บันทึก (ตั้งชื่อ "Quiz Live PLPN Mailer")
 *  2) เลือกฟังก์ชัน setup แล้วกด "เรียกใช้" → อนุญาตสิทธิ์ (อีเมล · Drive · เชื่อมต่อภายนอก) → ดู "บันทึกการดำเนินการ" จะเห็นรหัสลับ (TOKEN)
 *  3) ทำให้ใช้งานได้ › การทำให้ใช้งานได้รายการใหม่ › ประเภท: เว็บแอป
 *       ดำเนินการในฐานะ: ฉัน · ผู้ที่มีสิทธิ์เข้าถึง: ทุกคน → ทำให้ใช้งานได้ → คัดลอก URL (ลงท้าย /exec)
 *  4) ใน Quiz Live PLPN › กล่อง ⚙ ผู้ดูแลระบบ › อีเมลระบบ → วาง URL และรหัสลับ → บันทึก → ส่งอีเมลทดสอบ
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
  DriveApp.getRootFolder();          // อ่านลายเซ็นระบบเดิมใน Drive
  UrlFetchApp.fetch('https://www.google.com', { muteHttpExceptions: true }); // ดึงลายเซ็นจาก Supabase
  Logger.log('รหัสลับ (TOKEN) สำหรับใส่ใน Quiz Live PLPN: ' + t);
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
    var opt = { to: to.join(','), subject: m.subject || d.subject, htmlBody: m.html, body: m.text, name: d.from_name || 'Quiz Live PLPN' };
    if (d.reply_to && /@/.test(d.reply_to)) opt.replyTo = d.reply_to;
    if (d.kind === 'report') opt.attachments = reportPdfs_(d);
    MailApp.sendEmail(opt);
    return out({ ok: true, sent: to.length, quota: MailApp.getRemainingDailyQuota() });
  } catch (err) {
    return out({ ok: false, error: String(err) });
  }
}


// ---------- ไฟล์ PDF แนบ (ใบลงชื่อพร้อมลายเซ็น · รายงานสรุป) ----------
function esc_(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
function fname_(s) { return String(s || '').replace(/[\\/:*?"<>|]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80); }

/** ลายเซ็น → data URI · ลิงก์ชั่วคราวจาก Supabase (sig_url) หรือไฟล์ใน Drive ระบบเดิม (sig_drive) */
function loadSigs_(rows) {
  var urls = [], idx = [];
  rows.forEach(function (r, i) {
    ['sig', 'fin'].forEach(function (k) { if (r[k + '_url']) { urls.push({ url: r[k + '_url'], muteHttpExceptions: true }); idx.push([i, k]); } });
  });
  for (var s = 0; s < urls.length; s += 40) {
    var res = UrlFetchApp.fetchAll(urls.slice(s, s + 40));
    res.forEach(function (x, j) {
      var p = idx[s + j];
      if (x.getResponseCode() === 200) { var by = x.getBlob().getBytes(); rows[p[0]][p[1] + '_img'] = 'data:image/png;base64,' + Utilities.base64Encode(by); rows[p[0]][p[1] + '_wh'] = pngSize_(by); }
    });
  }
  rows.forEach(function (r) {
    ['sig', 'fin'].forEach(function (k) {
      if (!r[k + '_img'] && r[k + '_drive']) {
        try { var b = DriveApp.getFileById(r[k + '_drive']).getBlob();
              var by2 = b.getBytes(); r[k + '_img'] = 'data:' + (b.getContentType() || 'image/png') + ';base64,' + Utilities.base64Encode(by2); r[k + '_wh'] = pngSize_(by2); } catch (e) {}
      }
    });
  });
}

/** ขนาดรูป PNG จากหัวไฟล์ (กว้าง/สูง) · ไม่ใช่ PNG → null */
function pngSize_(by) {
  if (!by || by.length < 24 || (by[1] & 255) !== 0x50) return null;
  var n = function (i) { return ((by[i] & 255) << 24) + ((by[i + 1] & 255) << 16) + ((by[i + 2] & 255) << 8) + (by[i + 3] & 255); };
  return [n(16), n(20)];
}
/** ลายเซ็นย่อให้พอดีช่อง (กำหนดกว้าง×สูงจริง เพราะตัวแปลง PDF ไม่สนใจ max-width/max-height) */
function sigImg_(src, wh) {
  if (!src) return '';
  var W = 130, H = 34, w = W, h = H;
  if (wh && wh[0] > 0 && wh[1] > 0) { var k = Math.min(W / wh[0], H / wh[1]); w = Math.round(wh[0] * k); h = Math.round(wh[1] * k); }
  return '<img src="' + src + '" width="' + w + '" height="' + h + '" style="width:' + w + 'px;height:' + h + 'px">';
}

function signSheetHtml_(d) {
  var c = d.course || {}, sh = d.sheet || {}, rows = sh.rows || [], fin = !!sh.finish;
  var h = '<html><head><meta charset="utf-8"><style>' +
    '@page{size:A4 landscape;margin:8mm}body{font-family:Sarabun,Tahoma,sans-serif;font-size:12px;color:#000}' +
    'table{width:100%;border-collapse:collapse}th,td{border:1px solid #000;padding:2px 4px;vertical-align:middle}th{background:#eee;font-size:11.5px}' +
    'td.s{height:40px;text-align:center;padding:2px;overflow:hidden}tr{page-break-inside:avoid}thead{display:table-header-group}' +
    '.c{text-align:center}</style></head><body>' +
    '<table style="border:0;margin-bottom:6px"><tr><td style="border:0;width:22%">' + (d.logo ? (function () { var h = 40, w = d.logo_wh ? Math.round(d.logo_wh[0] * h / d.logo_wh[1]) : 220; if (w > 230) { h = Math.round(h * 230 / w); w = 230; } return '<img src="' + d.logo + '" width="' + w + '" height="' + h + '" style="width:' + w + 'px;height:' + h + 'px">'; })() : '') + '</td><td style="border:0;text-align:center">' +
    '<div style="font-size:13px;font-weight:bold">แบบลงทะเบียนผู้เข้าร่วมอบรม</div>' +
    '<div style="font-size:15px;font-weight:bold">' + esc_(c.cert_title || c.title) + '</div>' +
    '<div style="font-size:12px">' + esc_(sh.label || 'ทุกวัน / ทุกรอบ') + (c.location ? ' · ' + esc_(c.location) : '') + '</div></td><td style="border:0;width:22%"></td></tr></table>' +
    '<table><thead><tr><th style="width:5%">ที่</th><th style="width:11%">รหัสพนักงาน</th><th>ชื่อ - นามสกุล</th><th style="width:19%">แผนก</th>' +
    '<th style="width:13%">วันที่ / รอบที่อบรม</th><th style="width:15%">ลงทะเบียนอบรม<br><span style="font-weight:normal">(ลายเซ็น)</span></th>' +
    (fin ? '<th style="width:15%">บันทึกหลังอบรม<br><span style="font-weight:normal">(ลายเซ็น)</span></th>' : '') + '</tr></thead><tbody>';
  rows.forEach(function (r, i) {
    h += '<tr><td class="c">' + (i + 1) + '</td><td class="c">' + esc_(r.emp_id) + '</td><td>' + esc_(r.name) + (r.late ? ' <i style="font-size:10px">(ย้อนหลัง)</i>' : '') + '</td><td>' + esc_(r.dept) + '</td>' +
      '<td class="c" style="font-size:10.5px;line-height:1.25">' + esc_(r.when) + '<br>' + esc_(r.round) + '</td>' +
      '<td class="s">' + sigImg_(r.sig_img, r.sig_wh) + '</td>' + (fin ? '<td class="s">' + sigImg_(r.fin_img, r.fin_wh) + '</td>' : '') + '</tr>';
  });
  if (!rows.length) h += '<tr><td colspan="' + (fin ? 7 : 6) + '" class="c" style="padding:12px">ไม่มีรายชื่อ</td></tr>';
  h += '</tbody></table><div style="font-size:10px;text-align:right;margin-top:4px">รวม ' + rows.length + ' คน · สร้างจาก Quiz Live PLPN เมื่อ ' +
    Utilities.formatDate(new Date(), 'Asia/Bangkok', 'dd/MM/yyyy HH:mm') + ' น.</div></body></html>';
  return h;
}

function summaryHtml_(d) {
  var c = d.course || {}, s = d.summary || {}, B = 'border:1px solid #000;padding:3px 5px';
  var h = '<html><head><meta charset="utf-8"><style>@page{size:A4;margin:10mm}body{font-family:Sarabun,Tahoma,sans-serif;font-size:12px}table{width:100%;border-collapse:collapse;margin-bottom:8px}th{background:#eee}tr{page-break-inside:avoid}</style></head><body>' +
    '<div style="text-align:center;margin-bottom:8px"><div style="font-size:15px;font-weight:bold">รายงานสรุปผู้เข้าอบรม (เทียบการจองกับผู้เข้าอบรมจริง)</div>' +
    '<div style="font-size:13px">' + esc_(c.cert_title || c.title) + '</div><div style="font-size:11px">ข้อมูล ณ ' + Utilities.formatDate(new Date(d.asof || new Date()), 'Asia/Bangkok', 'dd/MM/yyyy HH:mm') + ' น.</div></div>' +
    '<table><tr>' + [['อบรมแล้ว', s.attended], ['ทั้งหมด', s.total || '-'], ['คิดเป็น', s.total ? s.percent + '%' : '-'], ['จองและมา', s.bookedAttended], ['จองแต่ไม่มา', s.absentPast],
      ['วันนี้จองแต่ยังไม่มา', s.absentToday], ['ไม่จองแต่มา', s.notBooked], ['ลงทะเบียนใหม่หน้างาน', s.walkin]]
      .map(function (x) { return '<td style="' + B + ';text-align:center">' + x[0] + '<br><b style="font-size:16px">' + x[1] + '</b></td>'; }).join('') + '</tr></table>';
  var rr = d.rounds || [];
  if (rr.length) h += '<div style="font-weight:bold;margin:6px 0 2px">รายรอบ</div><table><tr><th style="' + B + '">รอบ</th><th style="' + B + '">จอง</th><th style="' + B + '">มา</th></tr>' +
    rr.map(function (r) { return '<tr><td style="' + B + '">' + esc_(r.label) + '</td><td style="' + B + ';text-align:right">' + r.booked + '</td><td style="' + B + ';text-align:right">' + r.attended + '</td></tr>'; }).join('') + '</table>';
  h += '<div style="font-weight:bold;margin:6px 0 2px">รายแผนก</div><table><tr>' + ['แผนก', 'เป้าหมาย', 'จอง', 'เข้าอบรม', '%'].map(function (t) { return '<th style="' + B + '">' + t + '</th>'; }).join('') + '</tr>' +
    (d.depts || []).map(function (x) { return '<tr><td style="' + B + '">' + esc_(x.dept) + '</td><td style="' + B + ';text-align:right">' + (x.target || '-') + '</td><td style="' + B + ';text-align:right">' + x.booked +
      '</td><td style="' + B + ';text-align:right">' + x.attended + '</td><td style="' + B + ';text-align:right">' + (x.target ? x.percent + '%' : '-') + '</td></tr>'; }).join('') + '</table>';
  var ab = (d.absent || []).filter(function (a) { return a.state !== 'ยังไม่ถึงวันจอง'; });
  if (ab.length) h += '<div style="font-weight:bold;margin:10px 0 2px">จองแล้วแต่ไม่ได้ลงชื่อ (' + ab.length + ' คน)</div><table><tr>' +
    ['รหัส', 'ชื่อ-นามสกุล', 'แผนก', 'วัน/รอบจอง', 'สถานะ'].map(function (t) { return '<th style="' + B + '">' + t + '</th>'; }).join('') + '</tr>' +
    ab.map(function (a) { return '<tr><td style="' + B + '">' + esc_(a.emp_id) + '</td><td style="' + B + '">' + esc_(a.name) + '</td><td style="' + B + '">' + esc_(a.dept) + '</td><td style="' + B + '">' + esc_(a.round) + '</td><td style="' + B + '">' + esc_(a.state) + '</td></tr>'; }).join('') + '</table>';
  return h + '</body></html>';
}

function reportPdfs_(d) {
  var out = [], c = d.course || {}, p = d.parts || {};
  if (p.summary_pdf) out.push(Utilities.newBlob(summaryHtml_(d), 'text/html', 'r.html').getAs('application/pdf').setName(fname_('สรุปผู้เข้าอบรม ' + c.title) + '.pdf'));
  if (p.sheet && d.sheet) {
    loadSigs_(d.sheet.rows || []);
    try { var lg = d.logo_url === 'none' ? null : UrlFetchApp.fetch(d.logo_url || (String(d.site || 'https://plpnquiz.pages.dev/').replace(/[#?].*$/, '').replace(/\/?$/, '/') + 'logo-hospitals.png'), { muteHttpExceptions: true });
          if (lg && lg.getResponseCode() === 200) { var lb = lg.getBlob().getBytes(); d.logo = 'data:' + (lg.getHeaders()['Content-Type'] || 'image/png') + ';base64,' + Utilities.base64Encode(lb); d.logo_wh = pngSize_(lb); } } catch (e) {}
    out.push(Utilities.newBlob(signSheetHtml_(d), 'text/html', 's.html').getAs('application/pdf').setName(fname_('ใบลงชื่อ ' + c.title + ' ' + (d.sheet.label || '')) + '.pdf'));
  }
  return out;
}

/** ทดสอบสิทธิ์ Drive/UrlFetch ก่อนใช้จริง (เรียกครั้งเดียวหลังอัปเดตโค้ด) */
function authorizeExtras() { DriveApp.getRootFolder(); UrlFetchApp.fetch('https://www.google.com', { muteHttpExceptions: true }); Logger.log('อนุญาตสิทธิ์ Drive และ UrlFetch แล้ว'); }
// ===== แม่แบบอีเมล Quiz Live PLPN (ใช้ร่วมกันทั้งหน้าเว็บและ Apps Script) =====
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
      return { subject: '[Quiz Live PLPN] คุณได้รับเชิญเป็นผู้จัดร่วม · ' + c.title,
        html: shell('Quiz Live PLPN · ระบบงานอบรม', body, 'ถ้าไม่ได้คาดว่าจะได้รับเมลนี้ ตอบกลับเพื่อแจ้งผู้เชิญได้ · อีเมลนี้ส่งจาก Quiz Live PLPN'),
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
      return { subject: d.subject, html: shell('Quiz Live PLPN · แจ้งเตือนงานอบรม · ' + c.title, body,
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
      return { subject: d.subject, html: shell('Quiz Live PLPN · สรุปงานอบรม · ' + c.title, body,
        'ส่งเฉพาะวันที่มีความเคลื่อนไหว · ส่งถึงเจ้าของงานและผู้จัดร่วม · ตั้งค่าได้ที่ งานอบรม › ตั้งค่า › การแจ้งเตือนทางอีเมล'),
        text: 'สรุป ' + c.title + ': จองใหม่ ' + n('จอง') + ' ย้าย ' + n('ย้ายรอบ') + ' ยกเลิก ' + n('ยกเลิกจอง') + '\n' + url + '\n' };
    },
    // สรุปการเข้าอบรมทั้งงาน (ผู้จัดกดส่งเอง) · ใบลงชื่อ/รายงานแนบเป็น PDF (สร้างใน Apps Script)
    report: function (d) {
      var c = d.course || {}, s = d.summary || {}, url = link(d.site, '#course/' + c.id + ':attend');
      function kpi(v, t, sub, bg, fg) { return '<td width="33%" style="padding:4px;vertical-align:top"><div style="background:' + bg + ';border-radius:10px;padding:10px 6px;text-align:center">' +
        '<div style="font-size:13px;color:#475569">' + t + '</div><div style="font-size:26px;font-weight:700;color:' + fg + '">' + v + '</div>' + (sub ? '<div style="font-size:12px;color:#64748b">' + sub + '</div>' : '') + '</div></td>'; }
      var TD = 'padding:5px 6px;border-bottom:1px solid #f1f5f9', TH = 'padding:5px 6px;border-bottom:1px solid #e2e8f0;color:#64748b;font-weight:600;font-size:13px';
      var parts = [];
      parts.push('<div style="font-size:21px;font-weight:700">สรุปการเข้าอบรม</div><div style="color:#64748b;font-size:14px;margin-bottom:10px">' + esc(c.cert_title || c.title) + '<br>ข้อมูล ณ ' + esc(dateTH(d.asof, true) + ' ' + timeTH(d.asof)) + ' น.</div>');
      parts.push('<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>' +
        kpi(s.attended, 'อบรมแล้ว', 'คน', '#e3efff', '#1e3a8a') + kpi(s.total || '-', 'ทั้งหมด', s.total ? 'คนในรายชื่อ' : 'ไม่มีรายชื่อเป้าหมาย', '#f1f5f9', '#0f172a') +
        kpi(s.total ? s.percent + '%' : '-', 'คิดเป็น', 'ความคืบหน้า', '#dff3e8', '#1b6b42') + '</tr></table>');
      parts.push('<div style="font-size:13px;color:#475569;text-align:center;margin:6px 0 14px">จองไว้ล่วงหน้า <b>' + s.bookedAttended + '</b> · ไม่ได้จอง <b>' + s.notBooked + '</b> · ลงทะเบียนใหม่หน้างาน <b>' + s.walkin + '</b>' +
        (s.finish != null ? ' · ลงชื่อหลังอบรม <b>' + s.finish + '</b>' : '') + (s.late ? ' · ลงชื่อย้อนหลัง <b>' + s.late + '</b>' : '') + '</div>');
      if (s.booked) parts.push('<div style="font-weight:700;margin:4px 0">เทียบการจองกับผู้เข้าอบรมจริง</div><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>' +
        kpi(s.bookedAttended, 'จองและมา', '', '#dff3e8', '#1b6b42') + kpi(s.absentPast, 'จองแต่ไม่มา', [s.absentToday ? 'วันนี้ยังไม่มา ' + s.absentToday : '', s.upcoming ? 'ยังไม่ถึงวัน ' + s.upcoming : ''].filter(Boolean).join(' · '), '#fde8e8', '#a32020') +
        kpi(s.notBooked, 'ไม่จองแต่มา', '', '#fff1d6', '#8a5a00') + '</tr></table>');
      var rr = d.rounds || [];
      if (rr.length) parts.push('<div style="font-weight:700;margin:14px 0 4px">รายรอบ</div><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:14px">' +
        '<tr><td style="' + TH + '">รอบ</td><td align="right" style="' + TH + '">จอง</td><td align="right" style="' + TH + '">มา</td></tr>' +
        rr.map(function (r) { return '<tr><td style="' + TD + '">' + esc(r.label) + (r.starts_at ? ' <span style="color:#64748b">· ' + esc(dateTH(r.starts_at)) + '</span>' : '') + '</td><td align="right" style="' + TD + '">' + r.booked + '</td><td align="right" style="' + TD + '"><b>' + r.attended + '</b></td></tr>'; }).join('') + '</table>');
      var dp = d.depts || [];
      if (dp.length) parts.push('<div style="font-weight:700;margin:14px 0 4px">ความคืบหน้ารายแผนก (น้อยไปมาก)</div><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:13.5px">' +
        '<tr><td style="' + TH + '">แผนก</td><td align="right" style="' + TH + '">เป้าหมาย</td><td align="right" style="' + TH + '">จอง</td><td align="right" style="' + TH + '">อบรม</td><td align="right" style="' + TH + '">%</td></tr>' +
        dp.map(function (x) { return '<tr><td style="' + TD + '">' + esc(x.dept) + '</td><td align="right" style="' + TD + '">' + (x.target || '-') + '</td><td align="right" style="' + TD + '">' + x.booked + '</td><td align="right" style="' + TD + '">' + x.attended +
          '</td><td align="right" style="' + TD + ';font-weight:700;color:' + (x.target && x.percent < 50 ? '#a32020' : '#1b6b42') + '">' + (x.target ? x.percent + '%' : '-') + '</td></tr>'; }).join('') + '</table>');
      var ab = (d.absent || []).filter(function (a) { return a.state !== 'ยังไม่ถึงวันจอง'; });
      if (ab.length) parts.push('<div style="font-weight:700;margin:14px 0 4px">จองแล้วแต่ยังไม่ได้ลงชื่อ (' + ab.length + ' คน)</div><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:13px">' +
        ab.slice(0, 80).map(function (a) { return '<tr><td style="' + TD + '">' + esc(a.emp_id) + '</td><td style="' + TD + '">' + esc(a.name) + '<br><span style="color:#64748b">' + esc(a.dept) + '</span></td><td style="' + TD + '">' + esc(a.round) +
          '</td><td style="' + TD + ';color:' + (a.state === 'ไม่มา' ? '#a32020' : '#8a5a00') + ';white-space:nowrap">' + esc(a.state) + '</td></tr>'; }).join('') +
        (ab.length > 80 ? '<tr><td colspan="4" style="' + TD + ';color:#64748b">… และอีก ' + (ab.length - 80) + ' คน (ดูในไฟล์ PDF แนบ)</td></tr>' : '') + '</table>');
      var att = [];
      if ((d.parts || {}).sheet) att.push('ใบลงชื่อพร้อมลายเซ็น' + (d.sheet && d.sheet.label ? ' (' + d.sheet.label + ')' : ''));
      if ((d.parts || {}).summary_pdf) att.push('รายงานสรุป');
      parts.push('<div style="margin:18px 0 0">' + (att.length ? '<div style="font-size:14px;margin-bottom:12px">📎 ไฟล์แนบ: ' + esc(att.join(' และ ')) + ' (PDF)</div>' : '') + btn(url, 'เปิดงานอบรม') + '</div>');
      return { subject: d.subject, html: shell('Quiz Live PLPN · สรุปงานอบรม · ' + c.title, parts.join(''), 'ส่งโดย ' + esc(d.sender_name || '') + ' ผ่าน Quiz Live PLPN · ตอบกลับเพื่อติดต่อผู้ส่ง'),
        text: 'สรุปการเข้าอบรม ' + c.title + '\nอบรมแล้ว ' + s.attended + (s.total ? ' / ' + s.total + ' (' + s.percent + '%)' : '') + ' คน\n' + url + '\n' };
    },
    test: function (d) {
      return { subject: d.subject || '[Quiz Live PLPN] ทดสอบการส่งอีเมล', html: shell('Quiz Live PLPN', '<div style="font-size:20px;font-weight:700">ส่งอีเมลได้แล้ว ✓</div><p>ระบบอีเมลของ Quiz Live PLPN เชื่อมกับ Apps Script เรียบร้อย</p>', 'อีเมลทดสอบจาก Quiz Live PLPN'),
        text: 'ระบบอีเมลของ Quiz Live PLPN เชื่อมกับ Apps Script เรียบร้อย' };
    }
  };
})();
