/**
 * Quiz Live — กันโปรเจกต์ Supabase (แพ็กเกจฟรี) ถูกพักเพราะไม่มีการใช้งาน
 *
 * ตั้งค่าครั้งเดียว:
 * 1) Project Settings (รูปเฟือง) > Script Properties > เพิ่ม
 *      SUPABASE_URL       = https://xxxxxxxx.supabase.co
 *      SUPABASE_ANON_KEY  = Publishable key หรือ anon public key
 * 2) เลือกฟังก์ชัน setup แล้วกด Run (อนุญาตสิทธิ์ครั้งแรก)
 *    ระบบจะเรียก Supabase ทุกวันตอน 8 โมงเช้า ถ้าเรียกไม่สำเร็จ Google จะส่งอีเมลแจ้งเจ้าของสคริปต์
 */
function setup() {
  ScriptApp.getProjectTriggers()
    .filter(function (t) { return t.getHandlerFunction() === 'keepAlive'; })
    .forEach(function (t) { ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('keepAlive').timeBased().everyDays(1).atHour(8).create();
  keepAlive();
}

function keepAlive() {
  var props = PropertiesService.getScriptProperties();
  var url = (props.getProperty('SUPABASE_URL') || '').replace(/\/+$/, '');
  var key = props.getProperty('SUPABASE_ANON_KEY') || '';
  if (!url || !key) throw new Error('ยังไม่ได้ตั้ง Script Properties: SUPABASE_URL และ SUPABASE_ANON_KEY');

  var headers = { apikey: key };
  if (key.indexOf('sb_') !== 0) headers.Authorization = 'Bearer ' + key;   // คีย์แบบเดิม (anon JWT)

  var res = UrlFetchApp.fetch(url + '/rest/v1/rpc/ping', {
    method: 'post', contentType: 'application/json', payload: '{}',
    headers: headers, muteHttpExceptions: true
  });
  var code = res.getResponseCode();
  Logger.log(code + ' ' + res.getContentText());
  if (code >= 300) throw new Error('เรียก Supabase ไม่สำเร็จ (' + code + '): ' + res.getContentText());
}
