// รูปประจำตัวผู้เล่น — ภาพ SVG วาดขึ้นใหม่ทั้งหมด (สัตว์น่ารัก + บุคลากรโรงพยาบาล)
// เพิ่ม/แก้รูปได้ที่ไฟล์นี้ไฟล์เดียว: แต่ละรูปคือ { id, name, group, svg }
(function () {
  let n = 0;   // id ไม่ซ้ำกัน เผื่อหลายรูปอยู่ในหน้าเดียว
  const wrap = (bg, body) => { const id = 'qlav' + (n++);
    return `<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><defs><clipPath id="${id}"><circle cx="50" cy="50" r="50"/></clipPath></defs>` +
      `<g clip-path="url(#${id})"><rect width="100" height="100" fill="${bg}"/>${body}</g></svg>`; };
  const INK = '#2b2b3a';
  const eyes = (y = 52, dx = 11, cx = 50, r = 3.6) =>
    `<circle cx="${cx - dx}" cy="${y}" r="${r}" fill="${INK}"/><circle cx="${cx + dx}" cy="${y}" r="${r}" fill="${INK}"/>` +
    `<circle cx="${cx - dx + 1.2}" cy="${y - 1.3}" r="1.1" fill="#fff"/><circle cx="${cx + dx + 1.2}" cy="${y - 1.3}" r="1.1" fill="#fff"/>`;
  const blush = (y = 60, dx = 18, cx = 50) =>
    `<ellipse cx="${cx - dx}" cy="${y}" rx="5" ry="3" fill="#ff8fa3" opacity=".55"/><ellipse cx="${cx + dx}" cy="${y}" rx="5" ry="3" fill="#ff8fa3" opacity=".55"/>`;
  const smile = (y = 61, w = 6, cx = 50) =>
    `<path d="M${cx - w} ${y} Q${cx} ${y + w * .9} ${cx + w} ${y}" fill="none" stroke="${INK}" stroke-width="2.4" stroke-linecap="round"/>`;
  const catMouth = (y = 63) =>
    `<path d="M44 ${y} Q47 ${y + 4} 50 ${y} Q53 ${y + 4} 56 ${y}" fill="none" stroke="${INK}" stroke-width="2.2" stroke-linecap="round"/>`;

  // ---------- สัตว์ ----------
  const animals = [
    { id: 'cat', name: 'แมวส้ม', svg: wrap('#ffe6c7',
      `<path d="M22 44 L26 14 L44 30 Z M78 44 L74 14 L56 30 Z" fill="#f29a4a"/>
       <path d="M27 36 L29 21 L39 30 Z M73 36 L71 21 L61 30 Z" fill="#ffb3c1"/>
       <ellipse cx="50" cy="56" rx="32" ry="28" fill="#f29a4a"/>
       <path d="M50 30 l-5 10 h10 z" fill="#d9772b"/><path d="M38 31 l-3 8 h7z M62 31 l3 8 h-7z" fill="#d9772b"/>
       <ellipse cx="50" cy="64" rx="14" ry="10" fill="#fff1e0"/>
       ${eyes(52, 12)}<path d="M47 58 h6 l-3 3z" fill="#ff7a93"/>${catMouth(61)}
       <path d="M30 60 h-12 M30 64 l-11 3 M70 60 h12 M70 64 l11 3" stroke="${INK}" stroke-width="1.4" stroke-linecap="round"/>`) },
    { id: 'dog', name: 'หมาน้อย', svg: wrap('#d7ebff',
      `<ellipse cx="50" cy="55" rx="30" ry="29" fill="#d9a066"/>
       <ellipse cx="22" cy="52" rx="10" ry="20" fill="#8a5a36" transform="rotate(15 22 52)"/>
       <ellipse cx="78" cy="52" rx="10" ry="20" fill="#8a5a36" transform="rotate(-15 78 52)"/>
       <ellipse cx="62" cy="44" rx="9" ry="8" fill="#8a5a36" opacity=".55"/>
       <ellipse cx="50" cy="66" rx="15" ry="11" fill="#fbe7cf"/>
       ${eyes(50, 11)}<ellipse cx="50" cy="61" rx="5" ry="3.6" fill="${INK}"/>
       <path d="M50 64 v3 M44 68 Q50 73 56 68" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>
       <path d="M48 70 q2 6 4 0" fill="#ff7a93"/>`) },
    { id: 'bear', name: 'หมีสีน้ำตาล', svg: wrap('#e4f4d4',
      `<circle cx="25" cy="30" r="11" fill="#9a6640"/><circle cx="75" cy="30" r="11" fill="#9a6640"/>
       <circle cx="25" cy="30" r="5.5" fill="#d6a479"/><circle cx="75" cy="30" r="5.5" fill="#d6a479"/>
       <circle cx="50" cy="55" r="31" fill="#9a6640"/>
       <ellipse cx="50" cy="65" rx="14" ry="11" fill="#e7c49c"/>
       ${eyes(51, 12)}${blush(60, 21)}<ellipse cx="50" cy="60" rx="4.5" ry="3.3" fill="${INK}"/>
       <path d="M45 66 Q50 70 55 66" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>`) },
    { id: 'rabbit', name: 'กระต่ายขาว', svg: wrap('#fde0ee',
      `<ellipse cx="37" cy="22" rx="8" ry="22" fill="#fff" transform="rotate(-8 37 22)"/>
       <ellipse cx="63" cy="22" rx="8" ry="22" fill="#fff" transform="rotate(8 63 22)"/>
       <ellipse cx="37" cy="23" rx="4" ry="15" fill="#ffb8cf" transform="rotate(-8 37 23)"/>
       <ellipse cx="63" cy="23" rx="4" ry="15" fill="#ffb8cf" transform="rotate(8 63 23)"/>
       <ellipse cx="50" cy="60" rx="29" ry="26" fill="#fff"/>
       ${eyes(56, 11)}${blush(64, 19)}<path d="M47 62 h6 l-3 3z" fill="#ff7a93"/>${catMouth(65)}
       <rect x="47.5" y="69" width="5" height="5" rx="1" fill="#fff" stroke="#e7d7de"/>`) },
    { id: 'panda', name: 'แพนด้า', svg: wrap('#d8f1ea',
      `<circle cx="26" cy="30" r="11" fill="${INK}"/><circle cx="74" cy="30" r="11" fill="${INK}"/>
       <circle cx="50" cy="55" r="31" fill="#fff"/>
       <ellipse cx="38" cy="52" rx="8" ry="10" fill="${INK}" transform="rotate(-25 38 52)"/>
       <ellipse cx="62" cy="52" rx="8" ry="10" fill="${INK}" transform="rotate(25 62 52)"/>
       <circle cx="39" cy="51" r="3.2" fill="#fff"/><circle cx="61" cy="51" r="3.2" fill="#fff"/>
       <circle cx="39.6" cy="51" r="1.6" fill="${INK}"/><circle cx="61.6" cy="51" r="1.6" fill="${INK}"/>
       ${blush(64, 20)}<ellipse cx="50" cy="62" rx="4.5" ry="3.2" fill="${INK}"/>
       <path d="M45 67 Q50 71 55 67" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>`) },
    { id: 'penguin', name: 'เพนกวิน', svg: wrap('#d8e7ff',
      `<ellipse cx="50" cy="60" rx="34" ry="36" fill="#2e3f5c"/>
       <path d="M50 38 C30 34 22 52 28 70 C34 86 66 86 72 70 C78 52 70 34 50 38 Z" fill="#fff"/>
       ${eyes(55, 10)}${blush(63, 18)}
       <path d="M44 61 L56 61 L50 68 Z" fill="#f7a531"/>
       <path d="M12 70 Q8 88 22 96 M88 70 Q92 88 78 96" stroke="#2e3f5c" stroke-width="9" fill="none" stroke-linecap="round"/>`) },
    { id: 'fox', name: 'จิ้งจอก', svg: wrap('#fff0d3',
      `<path d="M18 22 L36 40 L24 54 Z M82 22 L64 40 L76 54 Z" fill="#ea7a2f"/>
       <path d="M22 30 L32 41 L26 48 Z M78 30 L68 41 L74 48 Z" fill="${INK}" opacity=".75"/>
       <path d="M18 46 C18 30 34 26 50 26 C66 26 82 30 82 46 C82 66 62 86 50 86 C38 86 18 66 18 46 Z" fill="#ea7a2f"/>
       <path d="M18 50 C24 68 38 72 50 86 C62 72 76 68 82 50 C70 56 60 58 50 66 C40 58 30 56 18 50 Z" fill="#fff"/>
       ${eyes(50, 13)}<ellipse cx="50" cy="70" rx="4.5" ry="3.3" fill="${INK}"/>
       <path d="M46 75 Q50 78 54 75" fill="none" stroke="${INK}" stroke-width="1.8" stroke-linecap="round"/>`) },
    { id: 'elephant', name: 'ลูกช้าง', svg: wrap('#ebe5ff',
      `<circle cx="20" cy="50" r="18" fill="#9aa3c4"/><circle cx="80" cy="50" r="18" fill="#9aa3c4"/>
       <circle cx="20" cy="50" r="11" fill="#f2b8c6"/><circle cx="80" cy="50" r="11" fill="#f2b8c6"/>
       <circle cx="50" cy="50" r="27" fill="#aeb6d4"/>
       ${eyes(46, 11)}${blush(55, 17)}
       <path d="M44 56 C44 70 46 80 40 90 L48 92 C54 82 56 70 56 56 Z" fill="#aeb6d4"/>
       <path d="M45 66 h10 M46 74 h9" stroke="#8e97b8" stroke-width="1.6" stroke-linecap="round"/>
       <path d="M32 60 Q30 72 34 74 M68 60 Q70 72 66 74" stroke="#fff" stroke-width="4" stroke-linecap="round" fill="none"/>`) },
    { id: 'chick', name: 'ลูกเจี๊ยบ', svg: wrap('#e3f6ff',
      `<path d="M46 22 q4 -10 8 0 q4 -8 6 2" fill="none" stroke="#f2b705" stroke-width="3" stroke-linecap="round"/>
       <circle cx="50" cy="56" r="32" fill="#ffd93b"/>
       ${eyes(50, 12)}${blush(60, 21)}
       <path d="M43 57 L57 57 L50 65 Z" fill="#f28c28"/>
       <path d="M19 66 Q10 60 14 52 M81 66 Q90 60 86 52" stroke="#f2b705" stroke-width="5" fill="none" stroke-linecap="round"/>`) },
    { id: 'frog', name: 'กบเขียว', svg: wrap('#fff6d9',
      `<circle cx="32" cy="34" r="13" fill="#5cbf6a"/><circle cx="68" cy="34" r="13" fill="#5cbf6a"/>
       <ellipse cx="50" cy="62" rx="36" ry="27" fill="#5cbf6a"/>
       <circle cx="32" cy="34" r="8" fill="#fff"/><circle cx="68" cy="34" r="8" fill="#fff"/>
       <circle cx="33" cy="35" r="4" fill="${INK}"/><circle cx="69" cy="35" r="4" fill="${INK}"/>
       ${blush(64, 24)}
       <path d="M30 64 Q50 80 70 64" fill="none" stroke="${INK}" stroke-width="2.6" stroke-linecap="round"/>
       <circle cx="45" cy="54" r="1.4" fill="#2f7d3c"/><circle cx="55" cy="54" r="1.4" fill="#2f7d3c"/>`) }
  ];

  // ---------- บุคลากร รพ. ----------
  const SKIN = ['#f5d0ad', '#e9b88f', '#d7a072'];
  const bust = (cloth, skin) =>
    `<path d="M14 100 C14 80 30 72 50 72 C70 72 86 80 86 100 Z" fill="${cloth}"/>
     <rect x="44" y="62" width="12" height="13" rx="4" fill="${skin}"/>`;
  const head = (skin, cy = 46) =>
    `<circle cx="29" cy="${cy + 2}" r="5" fill="${skin}"/><circle cx="71" cy="${cy + 2}" r="5" fill="${skin}"/>
     <circle cx="50" cy="${cy}" r="21" fill="${skin}"/>`;
  const faceOn = (cy = 46) => eyes(cy + 2, 8, 50, 3) + blush(cy + 9, 13) + smile(cy + 10, 5);
  const coat = (shirt) =>
    `<path d="M14 100 C14 80 30 72 50 72 C70 72 86 80 86 100 Z" fill="#fff"/>
     <path d="M42 73 L50 92 L58 73 Z" fill="${shirt}"/>
     <path d="M42 73 L48 100 M58 73 L52 100" stroke="#d6dde4" stroke-width="2"/>
     <path d="M14 100 C14 80 30 72 50 72 C70 72 86 80 86 100" fill="none" stroke="#d6dde4" stroke-width="1.5"/>`;

  const staff = [
    { id: 'doctor', name: 'คุณหมอ', svg: wrap('#dbeeff',
      `${coat('#7fb6ec')}<rect x="44" y="62" width="12" height="12" rx="4" fill="${SKIN[0]}"/>${head(SKIN[0])}
       <path d="M29 42 C29 24 42 20 52 22 C64 22 72 30 71 42 C66 34 58 30 46 32 C38 33 33 37 29 42 Z" fill="#3a2a22"/>
       ${faceOn()}
       <path d="M36 76 C34 90 46 94 50 86 M64 76 C66 90 54 94 50 86" fill="none" stroke="#3d4a5c" stroke-width="2.4"/>
       <circle cx="50" cy="88" r="4" fill="#9aa8b8" stroke="#3d4a5c" stroke-width="1.5"/>
       <rect x="62" y="84" width="10" height="7" rx="1.5" fill="#2c7bd6"/>`) },
    { id: 'nurse', name: 'พยาบาล', svg: wrap('#ffe3ea',
      `${bust('#fff', SKIN[1])}<path d="M40 74 Q50 82 60 74" fill="none" stroke="#7fb6ec" stroke-width="3"/>
       <circle cx="50" cy="26" r="10" fill="#2f2320"/>
       ${head(SKIN[1], 48)}
       <path d="M29 46 C29 30 40 26 50 26 C60 26 71 30 71 46 C66 38 58 35 50 35 C42 35 34 38 29 46 Z" fill="#2f2320"/>
       <path d="M32 33 L36 22 L64 22 L68 33 Q50 28 32 33 Z" fill="#fff" stroke="#e6d4da" stroke-width="1.2"/>
       <path d="M48 23 h4 v3 h3 v4 h-3 v3 h-4 v-3 h-3 v-4 h3 z" fill="#e44d57"/>
       ${faceOn(48)}`) },
    { id: 'surgeon', name: 'ศัลยแพทย์', svg: wrap('#d6f3ec',
      `${bust('#2fa58a', SKIN[0])}<path d="M42 73 L50 84 L58 73" fill="none" stroke="#1f7c67" stroke-width="2"/>
       ${head(SKIN[0])}
       <path d="M28 44 C27 26 40 20 50 20 C62 20 74 26 72 44 C66 40 34 40 28 44 Z" fill="#3cbfa0"/>
       <circle cx="38" cy="30" r="1.6" fill="#fff" opacity=".7"/><circle cx="52" cy="26" r="1.6" fill="#fff" opacity=".7"/><circle cx="62" cy="33" r="1.6" fill="#fff" opacity=".7"/>
       ${eyes(46, 8, 50, 3)}
       <path d="M32 52 Q50 48 68 52 L66 64 Q50 72 34 64 Z" fill="#a7d8f0"/>
       <path d="M36 57 h28 M37 61 h26" stroke="#86c3e0" stroke-width="1.3"/>
       <path d="M32 53 L29 48 M68 53 L71 48" stroke="#a7d8f0" stroke-width="1.6"/>`) },
    { id: 'pharmacist', name: 'เภสัชกร', svg: wrap('#e5f6dc',
      `${coat('#7cc98e')}<rect x="44" y="62" width="12" height="12" rx="4" fill="${SKIN[2]}"/>${head(SKIN[2])}
       <path d="M29 46 C26 26 40 21 50 21 C62 21 75 27 71 46 C70 36 64 30 50 30 C40 30 32 34 29 46 Z" fill="#40291f"/>
       <path d="M28 44 C26 54 28 62 31 66 M72 44 C74 54 72 62 69 66" stroke="#40291f" stroke-width="5" stroke-linecap="round"/>
       <circle cx="42" cy="48" r="6.5" fill="none" stroke="#3d4a5c" stroke-width="2"/><circle cx="58" cy="48" r="6.5" fill="none" stroke="#3d4a5c" stroke-width="2"/>
       <path d="M48.5 48 h3" stroke="#3d4a5c" stroke-width="2"/>
       ${eyes(48, 8, 50, 2.6)}${smile(57, 5)}
       <g transform="rotate(-35 70 88)"><rect x="62" y="84" width="18" height="8" rx="4" fill="#fff" stroke="#d6dde4"/><path d="M66 84 h5 v8 h-5 a4 4 0 0 1 0 -8z" fill="#e44d57"/></g>`) },
    { id: 'medtech', name: 'นักเทคนิคการแพทย์', svg: wrap('#efe6ff',
      `${coat('#b9a6f0')}<rect x="44" y="62" width="12" height="12" rx="4" fill="${SKIN[1]}"/>${head(SKIN[1])}
       <path d="M29 42 C30 26 40 22 50 22 C60 22 70 26 71 42 L66 36 L60 40 L54 34 L46 40 L40 34 L34 40 Z" fill="#5a3a24"/>
       <rect x="31" y="40" width="38" height="12" rx="6" fill="#bfe6ff" opacity=".85" stroke="#6aa8d6" stroke-width="1.6"/>
       ${eyes(46, 8, 50, 2.8)}${blush(55, 13)}${smile(57, 5)}
       <g transform="rotate(20 70 88)"><rect x="66" y="76" width="8" height="20" rx="4" fill="#fff" stroke="#9aa8b8"/><rect x="66" y="86" width="8" height="10" rx="4" fill="#e44d57"/></g>`) },
    { id: 'porter', name: 'เวรเปล', svg: wrap('#fff1d6',
      `${bust('#2c7bd6', SKIN[2])}<path d="M44 73 L50 80 L56 73" fill="none" stroke="#fff" stroke-width="2.4"/>
       <rect x="60" y="82" width="12" height="6" rx="1.5" fill="#fff"/>
       ${head(SKIN[2])}
       <path d="M28 40 C28 24 40 19 50 19 C62 19 72 24 72 40 Z" fill="#2c7bd6"/>
       <path d="M44 40 C56 37 70 38 82 42 L80 45 C70 42 56 42 44 44 Z" fill="#1f5ea8"/>
       <circle cx="50" cy="28" r="3" fill="#ffc63d"/>
       ${faceOn()}`) },
    { id: 'it', name: 'ไอที', svg: wrap('#e1e8f2',
      `${bust('#24384f', SKIN[0])}<path d="M44 73 L50 80 L56 73" fill="none" stroke="#7fb6ec" stroke-width="2.4"/>
       ${head(SKIN[0])}
       <path d="M29 44 C27 24 42 19 52 21 C66 22 74 30 71 44 C68 34 62 30 54 31 C46 26 36 32 29 44 Z" fill="#222"/>
       <path d="M27 48 C27 22 73 22 73 48" fill="none" stroke="#3d4a5c" stroke-width="4"/>
       <rect x="23" y="42" width="8" height="13" rx="3.5" fill="#3d4a5c"/><rect x="69" y="42" width="8" height="13" rx="3.5" fill="#3d4a5c"/>
       <path d="M27 54 Q30 64 42 63" fill="none" stroke="#3d4a5c" stroke-width="2.4"/><circle cx="43" cy="63" r="2.6" fill="#e44d57"/>
       ${eyes(48, 8, 50, 3)}${smile(56, 4.5)}`) },
    { id: 'housekeeper', name: 'แม่บ้าน', svg: wrap('#ffe8f2',
      `${bust('#ef8fb4', SKIN[1])}<path d="M38 80 h24 v20 h-24 z" fill="#fff" opacity=".9"/>
       ${head(SKIN[1])}
       <path d="M29 48 C28 34 34 26 50 26 C66 26 72 34 71 48" fill="#3a2a22"/>
       <path d="M27 40 C27 22 73 22 73 40 C62 34 38 34 27 40 Z" fill="#ef8fb4"/>
       <circle cx="38" cy="30" r="2" fill="#fff"/><circle cx="50" cy="27" r="2" fill="#fff"/><circle cx="62" cy="30" r="2" fill="#fff"/>
       <path d="M72 36 l8 -4 l-2 8 z" fill="#ef8fb4"/>
       ${faceOn()}`) },
    { id: 'physio', name: 'นักกายภาพ', svg: wrap('#ddf3ff',
      `${bust('#f2a33a', SKIN[0])}<path d="M44 73 L50 80 L56 73" fill="none" stroke="#fff" stroke-width="2.4"/>
       ${head(SKIN[0])}
       <path d="M28 46 C24 24 44 18 54 22 C66 24 76 32 72 46 C70 36 62 30 52 32 C42 30 32 36 28 46 Z" fill="#6b3f22"/>
       <path d="M66 26 C74 28 80 38 74 52" fill="none" stroke="#6b3f22" stroke-width="7" stroke-linecap="round"/>
       ${faceOn()}
       <rect x="16" y="82" width="22" height="6" rx="3" fill="#3d4a5c"/><rect x="12" y="78" width="6" height="14" rx="2" fill="#3d4a5c"/><rect x="36" y="78" width="6" height="14" rx="2" fill="#3d4a5c"/>`) },
    { id: 'paramedic', name: 'กู้ชีพ', svg: wrap('#ffe5e0',
      `${bust('#e44d57', SKIN[2])}<path d="M14 92 h72" stroke="#ffd93b" stroke-width="4"/>
       <rect x="58" y="78" width="12" height="10" rx="2" fill="#fff"/><path d="M62.5 79.5 h3 v2.5 h2.5 v3 h-2.5 v2.5 h-3 v-2.5 h-2.5 v-3 h2.5 z" fill="#e44d57"/>
       ${head(SKIN[2])}
       <path d="M29 44 C28 26 40 21 50 21 C62 21 72 27 71 44 C66 36 60 32 50 32 C40 32 34 36 29 44 Z" fill="#1d1d1d"/>
       ${faceOn()}`) }
  ];

  // ---------- สัตว์ ชุด 2 ----------
  animals.push(
    { id: 'koala', name: 'โคอาล่า', svg: wrap('#e5edf5',
      `<circle cx="21" cy="38" r="16" fill="#8f9bab"/><circle cx="79" cy="38" r="16" fill="#8f9bab"/>
       <circle cx="21" cy="38" r="9.5" fill="#e3e7ee"/><circle cx="79" cy="38" r="9.5" fill="#e3e7ee"/>
       <circle cx="50" cy="56" r="28" fill="#a7b2c0"/>
       ${eyes(50, 13)}${blush(62, 19)}
       <ellipse cx="50" cy="60" rx="7" ry="9" fill="#3a3f4b"/><ellipse cx="48" cy="56" rx="2" ry="2.6" fill="#fff" opacity=".35"/>
       <path d="M45 72 Q50 75 55 72" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>`) },
    { id: 'pig', name: 'หมูชมพู', svg: wrap('#ffeae4',
      `<path d="M22 40 L24 18 L42 30 Z M78 40 L76 18 L58 30 Z" fill="#f191a8"/>
       <circle cx="50" cy="56" r="30" fill="#f7aebe"/>
       ${eyes(48, 13)}${blush(58, 22)}
       <ellipse cx="50" cy="62" rx="13" ry="9" fill="#f17f9b"/>
       <ellipse cx="45.5" cy="62" rx="2.4" ry="3.4" fill="#b04a66"/><ellipse cx="54.5" cy="62" rx="2.4" ry="3.4" fill="#b04a66"/>
       <path d="M45 75 Q50 78 55 75" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>`) },
    { id: 'monkey', name: 'ลิงน้อย', svg: wrap('#fff2d4',
      `<circle cx="19" cy="52" r="11" fill="#8a5a36"/><circle cx="81" cy="52" r="11" fill="#8a5a36"/>
       <circle cx="19" cy="52" r="6" fill="#f2c9a0"/><circle cx="81" cy="52" r="6" fill="#f2c9a0"/>
       <circle cx="50" cy="52" r="30" fill="#8a5a36"/>
       <path d="M50 40 C42 30 26 38 30 52 C30 62 36 74 50 76 C64 74 70 62 70 52 C74 38 58 30 50 40 Z" fill="#f2c9a0"/>
       ${eyes(50, 9)}${blush(60, 15)}
       <circle cx="47" cy="59" r="1.3" fill="${INK}"/><circle cx="53" cy="59" r="1.3" fill="${INK}"/>
       <path d="M42 65 Q50 72 58 65" fill="none" stroke="${INK}" stroke-width="2.2" stroke-linecap="round"/>
       <path d="M46 24 q4 -8 8 0" fill="none" stroke="#8a5a36" stroke-width="3" stroke-linecap="round"/>`) },
    { id: 'tiger', name: 'ลูกเสือ', svg: wrap('#fff0dc',
      `<circle cx="24" cy="30" r="10" fill="#f39a2e"/><circle cx="76" cy="30" r="10" fill="#f39a2e"/>
       <circle cx="24" cy="30" r="5" fill="#fff"/><circle cx="76" cy="30" r="5" fill="#fff"/>
       <circle cx="50" cy="55" r="31" fill="#f39a2e"/>
       <path d="M44 26 l3 9 l3 -9 l3 9 l3 -9" fill="none" stroke="${INK}" stroke-width="2.6" stroke-linejoin="round"/>
       <path d="M20 50 h9 M21 57 h8 M80 50 h-9 M79 57 h-8" stroke="${INK}" stroke-width="2.6" stroke-linecap="round"/>
       <ellipse cx="50" cy="66" rx="16" ry="12" fill="#fff"/>
       ${eyes(50, 12)}<path d="M46 60 h8 l-4 4z" fill="#ff7a93"/>${catMouth(65)}`) },
    { id: 'lion', name: 'ลูกสิงโต', svg: wrap('#fff6d4',
      `${[0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330].map(a => {
          const r = a * Math.PI / 180; return `<circle cx="${(50 + 31 * Math.cos(r)).toFixed(1)}" cy="${(54 + 31 * Math.sin(r)).toFixed(1)}" r="12" fill="#c9782e"/>`; }).join('')}
       <circle cx="50" cy="54" r="31" fill="#c9782e"/>
       <circle cx="30" cy="34" r="7" fill="#f2b84b"/><circle cx="70" cy="34" r="7" fill="#f2b84b"/>
       <circle cx="50" cy="56" r="23" fill="#f2b84b"/>
       <ellipse cx="50" cy="65" rx="11" ry="8" fill="#fff4d6"/>
       ${eyes(52, 9, 50, 3.2)}<path d="M46 60 h8 l-4 4z" fill="#7a4a24"/>${catMouth(65)}`) },
    { id: 'owl', name: 'นกฮูก', svg: wrap('#e2eeff',
      `<path d="M24 34 L28 16 L40 28 Z M76 34 L72 16 L60 28 Z" fill="#7a5a43"/>
       <ellipse cx="50" cy="60" rx="31" ry="34" fill="#8e6a50"/>
       <ellipse cx="50" cy="74" rx="18" ry="16" fill="#e9d3b8"/>
       <path d="M42 70 q3 3 6 0 M52 70 q3 3 6 0 M47 78 q3 3 6 0" fill="none" stroke="#c4a582" stroke-width="1.6"/>
       <circle cx="38" cy="46" r="12" fill="#fff"/><circle cx="62" cy="46" r="12" fill="#fff"/>
       <circle cx="39" cy="47" r="6" fill="${INK}"/><circle cx="61" cy="47" r="6" fill="${INK}"/>
       <circle cx="41" cy="45" r="2" fill="#fff"/><circle cx="63" cy="45" r="2" fill="#fff"/>
       <path d="M46 55 L54 55 L50 62 Z" fill="#f2a33a"/>`) },
    { id: 'hamster', name: 'แฮมสเตอร์', svg: wrap('#fff0e6',
      `<circle cx="27" cy="32" r="8" fill="#e8a76a"/><circle cx="73" cy="32" r="8" fill="#e8a76a"/>
       <circle cx="27" cy="32" r="4.5" fill="#ffb8c8"/><circle cx="73" cy="32" r="4.5" fill="#ffb8c8"/>
       <ellipse cx="50" cy="58" rx="36" ry="30" fill="#f2bf86"/>
       <ellipse cx="50" cy="70" rx="26" ry="18" fill="#fff6ea"/>
       <path d="M50 30 C46 38 46 46 50 50 C54 46 54 38 50 30 Z" fill="#fff6ea"/>
       ${eyes(52, 15)}${blush(64, 25)}
       <ellipse cx="50" cy="61" rx="3" ry="2.2" fill="#e8708a"/>
       <path d="M44 65 Q50 70 56 65" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>
       <rect x="47.5" y="67" width="5" height="4.5" rx="1" fill="#fff" stroke="#e8d8c8"/>`) },
    { id: 'sheep', name: 'แกะน้อย', svg: wrap('#e6f6e4',
      `${[[30, 30], [44, 22], [58, 22], [70, 30], [76, 44], [74, 58], [26, 58], [24, 44], [50, 30]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="13" fill="#fff"/>`).join('')}
       <ellipse cx="22" cy="54" rx="9" ry="5" fill="#e6c7a6" transform="rotate(-20 22 54)"/>
       <ellipse cx="78" cy="54" rx="9" ry="5" fill="#e6c7a6" transform="rotate(20 78 54)"/>
       <ellipse cx="50" cy="60" rx="21" ry="24" fill="#f3dcc2"/>
       ${[[38, 36], [50, 33], [62, 36]].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="9" fill="#fff"/>`).join('')}
       ${eyes(56, 9, 50, 3.2)}${blush(65, 14)}
       <path d="M46 68 Q50 72 54 68" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/>`) },
    { id: 'cow', name: 'วัวนม', svg: wrap('#e0f0ff',
      `<path d="M28 30 Q20 18 26 12 M72 30 Q80 18 74 12" fill="none" stroke="#f3e2b8" stroke-width="6" stroke-linecap="round"/>
       <ellipse cx="17" cy="44" rx="11" ry="6" fill="#fff" stroke="#e1e4ea"/><ellipse cx="83" cy="44" rx="11" ry="6" fill="#fff" stroke="#e1e4ea"/>
       <ellipse cx="50" cy="52" rx="28" ry="30" fill="#fff"/>
       <path d="M30 30 C38 26 46 34 42 42 C36 46 26 40 30 30 Z" fill="${INK}"/>
       <path d="M70 46 C76 44 80 52 76 58 C70 60 66 52 70 46 Z" fill="${INK}"/>
       ${eyes(48, 11)}
       <ellipse cx="50" cy="70" rx="19" ry="12" fill="#f7b6c4"/>
       <ellipse cx="43" cy="70" rx="3" ry="4" fill="#c46a82"/><ellipse cx="57" cy="70" rx="3" ry="4" fill="#c46a82"/>`) },
    { id: 'turtle', name: 'เต่าน้อย', svg: wrap('#dcf4ee',
      `<ellipse cx="50" cy="96" rx="44" ry="28" fill="#3f9b5a"/>
       <path d="M30 86 l10 -8 h20 l10 8 M40 78 v-0 M28 98 l12 -8 M72 98 l-12 -8 M40 90 h20" fill="none" stroke="#2f7a45" stroke-width="2.4"/>
       <circle cx="50" cy="48" r="25" fill="#8fd17a"/>
       ${eyes(46, 10)}${blush(55, 16)}${smile(56, 6)}
       <circle cx="38" cy="30" r="2" fill="#7bbd66"/><circle cx="60" cy="28" r="2.5" fill="#7bbd66"/>`) }
  );

  // ---------- บุคลากร ชุด 2 ----------
  const label = (txt, x, y, bg, fg = '#fff', w = 16) =>
    `<rect x="${x - w / 2}" y="${y - 5.5}" width="${w}" height="10" rx="2.5" fill="${bg}"/>` +
    `<text x="${x}" y="${y + 2.4}" font-family="Arial,Helvetica,sans-serif" font-weight="700" font-size="7.5" fill="${fg}" text-anchor="middle">${txt}</text>`;
  const shortHair = c => `<path d="M29 42 C29 24 42 20 52 22 C64 22 72 30 71 42 C66 34 58 30 46 32 C38 33 33 37 29 42 Z" fill="${c}"/>`;
  const bobHair = c => `<path d="M28 50 C25 28 38 21 50 21 C62 21 75 28 72 50 C70 40 66 32 50 32 C36 32 31 40 28 50 Z" fill="${c}"/>`;
  staff.push(
    { id: 'pn', name: 'PN', svg: wrap('#e3f1ff',
      `${bust('#fff', SKIN[0])}<path d="M40 74 Q50 82 60 74" fill="none" stroke="#2c7bd6" stroke-width="3"/>
       ${label('PN', 63, 86, '#2c7bd6')}
       ${head(SKIN[0], 48)}${bobHair('#2a201c')}
       <path d="M32 34 L36 24 L64 24 L68 34 Q50 29 32 34 Z" fill="#fff" stroke="#d3dde8" stroke-width="1.2"/>
       <path d="M34 31 Q50 27 66 31" stroke="#2c7bd6" stroke-width="3" fill="none"/>
       ${faceOn(48)}`) },
    { id: 'na', name: 'NA', svg: wrap('#dff6f6',
      `${bust('#5bbfcf', SKIN[1])}<path d="M42 73 L50 84 L58 73" fill="none" stroke="#3a9aab" stroke-width="2"/>
       ${label('NA', 63, 86, '#1f5f74')}
       <path d="M70 34 C82 40 82 56 74 62" fill="none" stroke="#2f2320" stroke-width="7" stroke-linecap="round"/>
       ${head(SKIN[1])}${shortHair('#2f2320')}
       <circle cx="69" cy="34" r="3" fill="#5bbfcf"/>
       ${faceOn()}`) },
    { id: 'finance', name: 'การเงิน', svg: wrap('#fff4d1',
      `${bust('#fff', SKIN[2])}<path d="M14 100 C14 80 30 72 50 72 C70 72 86 80 86 100" fill="none" stroke="#e1e4ea" stroke-width="1.5"/>
       <path d="M46 73 L54 73 L52 78 L55 96 L50 100 L45 96 L48 78 Z" fill="#1f4e8c"/>
       <circle cx="70" cy="88" r="9" fill="#f5c542" stroke="#d49e14" stroke-width="2"/>
       <text x="70" y="92.5" font-family="Arial,Helvetica,sans-serif" font-weight="700" font-size="12" fill="#9a6b00" text-anchor="middle">฿</text>
       ${head(SKIN[2])}${shortHair('#1d1d1d')}${faceOn()}`) },
    { id: 'admin', name: 'ธุรการ', svg: wrap('#e8edf5',
      `${bust('#4a6584', SKIN[0])}<path d="M42 73 L50 90 L58 73 Z" fill="#fff"/>
       <rect x="62" y="78" width="14" height="18" rx="2" fill="#fff" stroke="#c9d2de"/><rect x="66" y="76" width="6" height="4" rx="1" fill="#9aa8b8"/>
       <path d="M65 84 h8 M65 88 h8 M65 92 h5" stroke="#9aa8b8" stroke-width="1.5"/>
       ${head(SKIN[0])}${bobHair('#4a2f22')}${faceOn()}`) },
    { id: 'records', name: 'เวชระเบียน', svg: wrap('#f0e9ff',
      `${bust('#8e7cc3', SKIN[1])}<path d="M44 73 L50 80 L56 73" fill="none" stroke="#fff" stroke-width="2.4"/>
       <path d="M58 82 h8 l2 3 h12 v13 h-22 z" fill="#f2c46d"/><rect x="58" y="85" width="22" height="13" rx="1" fill="#f7d58c"/>
       ${head(SKIN[1])}${shortHair('#3a2a22')}
       <circle cx="42" cy="48" r="6" fill="none" stroke="#5a4a7a" stroke-width="1.8"/><circle cx="58" cy="48" r="6" fill="none" stroke="#5a4a7a" stroke-width="1.8"/>
       <path d="M48 48 h4" stroke="#5a4a7a" stroke-width="1.8"/>
       ${eyes(48, 8, 50, 2.6)}${smile(57, 5)}`) },
    { id: 'dietitian', name: 'โภชนากร', svg: wrap('#eaf7dc',
      `${bust('#fff', SKIN[2])}<path d="M32 78 L36 100 H64 L68 78 Q50 84 32 78 Z" fill="#8bc34a"/>
       <path d="M36 78 L44 72 M64 78 L56 72" stroke="#8bc34a" stroke-width="2.4"/>
       <circle cx="50" cy="24" r="9" fill="#3a2a22"/>
       ${head(SKIN[2], 47)}${bobHair('#3a2a22')}
       <circle cx="72" cy="88" r="7" fill="#e44d57"/><path d="M72 81 q2 -4 5 -4" stroke="#5a8f2a" stroke-width="2" fill="none"/>
       ${faceOn(47)}`) },
    { id: 'radiology', name: 'รังสีเทคนิค', svg: wrap('#e2e7f7',
      `${bust('#3b4f8c', SKIN[0])}<path d="M42 73 L50 84 L58 73" fill="none" stroke="#2a3a6c" stroke-width="2"/>
       <rect x="60" y="78" width="18" height="20" rx="2" fill="#1b2433" stroke="#9aa8b8"/>
       <path d="M69 81 v14 M64 84 q5 2 10 0 M63 88 q6 2 12 0 M64 92 q5 2 10 0" stroke="#e8eef6" stroke-width="1.4" fill="none"/>
       ${head(SKIN[0])}${shortHair('#2a2a2a')}${faceOn()}`) },
    { id: 'dentist', name: 'ทันตแพทย์', svg: wrap('#e0f6fb',
      `${coat('#7fd3e6')}<rect x="44" y="62" width="12" height="12" rx="4" fill="${SKIN[1]}"/>
       <path d="M62 80 C62 76 66 76 68 78 C70 76 74 76 74 80 C74 86 72 96 70 96 C68 96 69 88 68 88 C67 88 68 96 66 96 C64 96 62 86 62 80 Z" fill="#fff" stroke="#8fb8c8" stroke-width="1.5"/>
       ${head(SKIN[1])}${bobHair('#2f2320')}${faceOn()}`) },
    { id: 'thaimed', name: 'แพทย์แผนไทย', svg: wrap('#e6e9f7',
      `${bust('#2f3e7a', SKIN[2])}<path d="M44 73 L50 80 L56 73" fill="none" stroke="#5a6bb0" stroke-width="2.4"/>
       <path d="M30 86 h40" stroke="#5a6bb0" stroke-width="1.5" stroke-dasharray="3 3"/>
       <circle cx="71" cy="90" r="8" fill="#e8d3a8"/><path d="M65 85 q6 -8 12 0" fill="#e8d3a8"/>
       <path d="M71 80 v-6" stroke="#b58a4a" stroke-width="2.4" stroke-linecap="round"/>
       <path d="M66 84 q5 3 10 0" stroke="#b58a4a" stroke-width="1.6" fill="none"/>
       ${head(SKIN[2])}${shortHair('#1d1d1d')}${faceOn()}`) },
    { id: 'security', name: 'รปภ.', svg: wrap('#e7edf2',
      `${bust('#3d4c5e', SKIN[2])}<path d="M44 73 L50 80 L56 73" fill="none" stroke="#c9d2de" stroke-width="2.4"/>
       <rect x="18" y="78" width="14" height="5" rx="2" fill="#f5c542"/><rect x="68" y="78" width="14" height="5" rx="2" fill="#f5c542"/>
       <path d="M60 86 l4 -2 l4 2 v5 q-4 4 -8 0 z" fill="#f5c542"/>
       ${head(SKIN[2], 48)}
       <path d="M26 40 C26 24 40 18 50 18 C60 18 74 24 74 40 Z" fill="#2c3a4a"/>
       <rect x="24" y="38" width="52" height="6" rx="3" fill="#1d2733"/>
       <path d="M50 24 l2.4 4.8 5.2 .8 -3.8 3.6 .9 5.2 -4.7 -2.5 -4.7 2.5 .9 -5.2 -3.8 -3.6 5.2 -.8 z" fill="#f5c542"/>
       ${faceOn(48)}`) }
  );

  const list = [...animals.map(a => ({ ...a, group: 'สัตว์น่ารัก' })), ...staff.map(a => ({ ...a, group: 'บุคลากร รพ.' }))];
  const api = { list, byId: id => list.find(a => a.id === id) || null };
  if (typeof module !== 'undefined') module.exports = api; else window.AVATARS = api;
})();
