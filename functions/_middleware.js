// ย้ายระบบไปที่ plpn-tools.pages.dev/quiz-live — ลิงก์/QR เดิมของโดเมนนี้ส่งต่อไปที่ใหม่ (คง path และ ?c= ?t= ?pin= ไว้)
// preview.plpnquiz.pages.dev ไม่ถูกส่งต่อ (ใช้ทดสอบก่อนอัปโหลด)
const NEW_BASE = 'https://plpn-tools.pages.dev/quiz-live';
export async function onRequest({ request, next }) {
  const u = new URL(request.url);
  if (u.hostname === 'plpnquiz.pages.dev') {
    const path = u.pathname === '/' || u.pathname === '/index.html' ? '/' : u.pathname;
    return Response.redirect(NEW_BASE + path + u.search + u.hash, 301);
  }
  return next();
}
