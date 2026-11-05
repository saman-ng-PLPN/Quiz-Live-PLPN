// ตั้งค่าระบบ — แก้เฉพาะไฟล์นี้ ไม่ต้องแตะ index.html
// ค่าอยู่ที่ Supabase > Project Settings > API
window.QUIZ_CONFIG = {
  SUPABASE_URL: 'https://xxxxxxxx.supabase.co',
  SUPABASE_ANON_KEY: 'วาง Publishable key หรือ anon public key ตรงนี้',
  ALLOWED_DOMAIN: 'princgroup.com',   // อีเมลโดเมนที่สร้าง/จัดเกมได้ (ต้องตรงกับ app_config ในฐานข้อมูล)
  APP_NAME: 'Quiz Live',
  ORG_NAME: 'โรงพยาบาล'
};
