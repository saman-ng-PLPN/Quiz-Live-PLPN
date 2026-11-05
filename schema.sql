-- =====================================================================
--  Quiz Live — ระบบเกมตอบคำถามแบบเล่นพร้อมกัน (Supabase)
--  วิธีใช้: เปิด Supabase > SQL Editor > New query > วางทั้งไฟล์ > Run
--  รันซ้ำได้ (ไม่ลบข้อมูลเดิม)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 0) ตั้งค่าระบบ: โดเมนอีเมลที่อนุญาตให้สร้าง/จัดเกม
--    เปลี่ยนได้ภายหลัง: update app_config set allowed_domain = 'xxx.com';
-- ---------------------------------------------------------------------
create table if not exists public.app_config (
  id int primary key default 1 check (id = 1),
  allowed_domain text not null default 'princgroup.com'
);
insert into public.app_config (id) values (1) on conflict (id) do nothing;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    lower(auth.jwt() ->> 'email') like ('%@' || lower((select allowed_domain from app_config where id = 1))),
    false)
$$;

-- ผู้ดูแลระบบ: เห็น/แก้/ลบได้ทุกชุดคำถาม
-- เพิ่มคนแรกด้วย SQL:  insert into app_admins (email) values ('อีเมล@princgroup.com');
-- คนต่อไปเพิ่มจากหน้าเว็บได้
create table if not exists public.app_admins (
  email      text primary key check (email = lower(email)),
  added_by   text,
  created_at timestamptz not null default now()
);
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_staff()
     and exists (select 1 from app_admins where email = lower(auth.jwt() ->> 'email'))
$$;

-- ---------------------------------------------------------------------
-- 1) ตาราง
-- ---------------------------------------------------------------------
create table if not exists public.quizzes (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid(),
  owner_email text not null default coalesce(auth.jwt() ->> 'email', ''),
  department  text not null default '',
  title       text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.questions (
  id            uuid primary key default gen_random_uuid(),
  quiz_id       uuid not null references public.quizzes(id) on delete cascade,
  position      int  not null default 0,
  text          text not null check (char_length(text) between 1 and 500),
  image_url     text,
  choices       jsonb not null check (jsonb_typeof(choices) = 'array'
                                      and jsonb_array_length(choices) between 2 and 4),
  correct_index int  not null check (correct_index >= 0 and correct_index < jsonb_array_length(choices)),
  time_limit    int  not null default 20 check (time_limit between 5 and 120)
);
create index if not exists questions_quiz_idx on public.questions (quiz_id, position);

-- รอบการเล่น (เก็บสำเนาคำถามไว้ แก้ชุดคำถามระหว่างเล่นก็ไม่กระทบ)
create table if not exists public.sessions (
  id                  uuid primary key default gen_random_uuid(),
  quiz_id             uuid not null references public.quizzes(id) on delete cascade,
  host_id             uuid not null default auth.uid(),
  title               text not null,
  pin                 text not null,
  status              text not null default 'lobby'
                      check (status in ('lobby', 'question', 'reveal', 'ended')),
  current_index       int  not null default -1,
  questions           jsonb not null,
  total_questions     int  not null,
  question_started_at timestamptz,
  question_ends_at    timestamptz,
  created_at          timestamptz not null default now()
);
create unique index if not exists sessions_active_pin on public.sessions (pin) where status <> 'ended';

create table if not exists public.players (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.sessions(id) on delete cascade,
  nickname    text not null check (char_length(nickname) between 1 and 30),
  token       uuid not null default gen_random_uuid(),
  score       int  not null default 0,
  last_points int  not null default 0,
  joined_at   timestamptz not null default now(),
  unique (session_id, nickname)
);

create table if not exists public.answers (
  id             bigserial primary key,
  session_id     uuid not null references public.sessions(id) on delete cascade,
  player_id      uuid not null references public.players(id) on delete cascade,
  question_index int  not null,
  choice         int  not null,
  is_correct     boolean not null,
  points         int  not null,
  answered_at    timestamptz not null default now(),
  unique (player_id, question_index)
);
create index if not exists answers_session_idx on public.answers (session_id, question_index);

-- v2: รูปหน้าปก / สีคำตอบต่อข้อ / รูปในตัวเลือก
alter table public.quizzes   add column if not exists cover_url text;
-- v3: ส่วนตัว (false) / แชร์ให้ทุกแผนก (true)
alter table public.quizzes   add column if not exists shared boolean not null default false;
-- v4: รูปประจำตัวผู้เล่น (รหัสรูปจาก avatars.js)
alter table public.players   add column if not exists avatar text;
alter table public.sessions  add column if not exists cover_url text;
alter table public.questions add column if not exists colors jsonb;          -- ["#rrggbb", ...] ต่อตัวเลือก
alter table public.questions add column if not exists choice_images jsonb;   -- ["url" | "", ...] ต่อตัวเลือก

-- ---------------------------------------------------------------------
-- 2) สิทธิ์ (RLS) — ผู้เล่นไม่ต้องล็อกอิน เข้าถึงผ่านฟังก์ชันเท่านั้น
-- ---------------------------------------------------------------------
alter table public.app_config enable row level security;
alter table public.app_admins enable row level security;
alter table public.quizzes    enable row level security;
alter table public.questions  enable row level security;
alter table public.sessions   enable row level security;
alter table public.players    enable row level security;
alter table public.answers    enable row level security;

revoke all on public.app_admins from anon, authenticated;
revoke all on public.app_config, public.quizzes, public.questions,
              public.sessions, public.players, public.answers from anon;
-- ให้สิทธิ์ชัดเจน (ใช้ได้แม้ปิด "Automatically expose new tables")
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.quizzes, public.questions to authenticated;
grant select, delete on public.sessions to authenticated;
grant select on public.players, public.answers to authenticated;

drop policy if exists quizzes_read   on public.quizzes;
drop policy if exists quizzes_insert on public.quizzes;
drop policy if exists quizzes_update on public.quizzes;
drop policy if exists quizzes_delete on public.quizzes;
create policy quizzes_read   on public.quizzes for select to authenticated
  using (public.is_staff() and (owner_id = auth.uid() or shared or public.is_admin()));
create policy quizzes_insert on public.quizzes for insert to authenticated
  with check (public.is_staff() and owner_id = auth.uid());
create policy quizzes_update on public.quizzes for update to authenticated
  using (owner_id = auth.uid() or public.is_admin()) with check (owner_id = auth.uid() or public.is_admin());
create policy quizzes_delete on public.quizzes for delete to authenticated
  using (owner_id = auth.uid() or public.is_admin());

drop policy if exists questions_read  on public.questions;
drop policy if exists questions_write on public.questions;
-- เห็นคำถามได้เมื่อเห็นชุดคำถามนั้น (ตามสิทธิ์ของ quizzes)
create policy questions_read on public.questions for select to authenticated
  using (exists (select 1 from public.quizzes q where q.id = quiz_id));
create policy questions_write on public.questions for all to authenticated
  using (exists (select 1 from public.quizzes q where q.id = quiz_id and (q.owner_id = auth.uid() or public.is_admin())))
  with check (exists (select 1 from public.quizzes q where q.id = quiz_id and (q.owner_id = auth.uid() or public.is_admin())));

drop policy if exists sessions_host on public.sessions;
create policy sessions_host on public.sessions for select to authenticated using (host_id = auth.uid());
drop policy if exists sessions_host_delete on public.sessions;
create policy sessions_host_delete on public.sessions for delete to authenticated using (host_id = auth.uid());

drop policy if exists players_host on public.players;
create policy players_host on public.players for select to authenticated
  using (exists (select 1 from public.sessions s where s.id = session_id and s.host_id = auth.uid()));

drop policy if exists answers_host on public.answers;
create policy answers_host on public.answers for select to authenticated
  using (exists (select 1 from public.sessions s where s.id = session_id and s.host_id = auth.uid()));

-- ---------------------------------------------------------------------
-- 3) ฟังก์ชันฝั่งผู้จัด
-- ---------------------------------------------------------------------

-- บันทึกชุดคำถามทั้งชุดในครั้งเดียว (p_id = null คือสร้างใหม่)
drop function if exists public.save_quiz(uuid, text, text, text, jsonb);
drop function if exists public.save_quiz(uuid, text, text, text, jsonb, text);
create or replace function public.save_quiz(
  p_id uuid, p_title text, p_department text, p_description text, p_questions jsonb,
  p_cover text default null, p_shared boolean default false
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  if p_id is null then
    insert into quizzes (title, department, description, cover_url, shared)
    values (trim(p_title), trim(coalesce(p_department, '')), coalesce(p_description, ''), nullif(p_cover, ''),
            coalesce(p_shared, false))
    returning id into v_id;
  else
    update quizzes set title = trim(p_title), department = trim(coalesce(p_department, '')),
                       description = coalesce(p_description, ''), cover_url = nullif(p_cover, ''),
                       shared = coalesce(p_shared, false), updated_at = now()
     where id = p_id and (owner_id = auth.uid() or public.is_admin())
    returning id into v_id;
    if v_id is null then raise exception 'ไม่มีสิทธิ์แก้ไขชุดคำถามนี้'; end if;
    delete from questions where quiz_id = v_id;
  end if;

  insert into questions (quiz_id, position, text, image_url, choices, correct_index, time_limit,
                         colors, choice_images)
  select v_id, (t.ord - 1)::int, trim(t.q ->> 'text'), nullif(t.q ->> 'image_url', ''),
         t.q -> 'choices', (t.q ->> 'correct_index')::int, coalesce((t.q ->> 'time_limit')::int, 20),
         case when jsonb_typeof(t.q -> 'colors') = 'array'
               and not exists (select 1 from jsonb_array_elements_text(t.q -> 'colors') c
                                where c !~ '^#[0-9a-fA-F]{6}$')
              then t.q -> 'colors' end,
         case when jsonb_typeof(t.q -> 'choice_images') = 'array' then t.q -> 'choice_images' end
    from jsonb_array_elements(coalesce(p_questions, '[]'::jsonb)) with ordinality as t(q, ord);
  return v_id;
end $$;

-- คัดลอกชุดคำถามของแผนกอื่นมาเป็นของตัวเอง
create or replace function public.duplicate_quiz(p_id uuid)
returns uuid language plpgsql security invoker set search_path = public as $$
declare v_src quizzes; v_id uuid;
begin
  select * into v_src from quizzes where id = p_id;
  if v_src.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  insert into quizzes (title, department, description, cover_url)
  values (left(v_src.title || ' (สำเนา)', 200), v_src.department, v_src.description, v_src.cover_url)
  returning id into v_id;
  insert into questions (quiz_id, position, text, image_url, choices, correct_index, time_limit,
                         colors, choice_images)
  select v_id, position, text, image_url, choices, correct_index, time_limit, colors, choice_images
    from questions where quiz_id = p_id;
  return v_id;
end $$;

-- เปิดห้องเกม ได้รหัส PIN 6 หลัก
create or replace function public.create_session(p_quiz_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_pin text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin()) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;

  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices,
           'correct', correct_index, 'time', time_limit,
           'colors', colors, 'images', choice_images) order by position), count(*)
    into v_qs, v_n
    from questions where quiz_id = p_quiz_id;
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีคำถาม'; end if;

  loop
    v_pin := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from sessions where pin = v_pin and status <> 'ended');
    i := i + 1;
    if i > 50 then raise exception 'สร้างรหัสห้องไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;

  insert into sessions (quiz_id, host_id, title, pin, questions, total_questions, cover_url)
  values (p_quiz_id, auth.uid(), v_quiz.title, v_pin, v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('session_id', v_id, 'pin', v_pin);
end $$;

-- ไปข้อถัดไป (จากหน้ารอ หรือหลังเฉลย) — ถ้าหมดข้อจะจบเกม
create or replace function public.host_next(p_session uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions; v_idx int; v_time int;
begin
  select * into s from sessions where id = p_session and host_id = auth.uid() for update;
  if s.id is null then raise exception 'ไม่พบห้องเกม หรือไม่มีสิทธิ์'; end if;
  if s.status = 'question' then raise exception 'ต้องเฉลยข้อนี้ก่อน'; end if;
  if s.status = 'ended' then return jsonb_build_object('status', 'ended'); end if;

  v_idx := s.current_index + 1;
  if v_idx >= s.total_questions then
    update sessions set status = 'ended' where id = p_session;
    return jsonb_build_object('status', 'ended');
  end if;
  v_time := (s.questions -> v_idx ->> 'time')::int;
  update sessions
     set status = 'question', current_index = v_idx,
         question_started_at = now(), question_ends_at = now() + make_interval(secs => v_time)
   where id = p_session;
  return jsonb_build_object('status', 'question', 'index', v_idx, 'remaining', v_time);
end $$;

-- เฉลย: บวกคะแนนของข้อนี้เข้าคะแนนรวม
create or replace function public.host_reveal(p_session uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions;
begin
  select * into s from sessions where id = p_session and host_id = auth.uid() for update;
  if s.id is null then raise exception 'ไม่พบห้องเกม หรือไม่มีสิทธิ์'; end if;
  if s.status <> 'question' then return jsonb_build_object('status', s.status); end if;

  update players p
     set score = p.score + coalesce(a.points, 0), last_points = coalesce(a.points, 0)
    from players pl
    left join answers a on a.player_id = pl.id and a.question_index = s.current_index
   where pl.session_id = p_session and p.id = pl.id;

  update sessions set status = 'reveal' where id = p_session;
  return jsonb_build_object('status', 'reveal');
end $$;

create or replace function public.host_end(p_session uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update sessions set status = 'ended' where id = p_session and host_id = auth.uid();
end $$;

create or replace function public.host_kick(p_player uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from players p using sessions s
   where p.id = p_player and s.id = p.session_id and s.host_id = auth.uid();
end $$;

-- ---------------------------------------------------------------------
-- 4) ฟังก์ชันฝั่งผู้เล่น (ไม่ต้องล็อกอิน ใช้ player_id + token)
-- ---------------------------------------------------------------------
drop function if exists public.join_game(text, text);
create or replace function public.join_game(p_pin text, p_nickname text, p_avatar text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sessions; v_name text := trim(coalesce(p_nickname, '')); p players;
begin
  if char_length(v_name) < 1 or char_length(v_name) > 30 then
    raise exception 'กรุณาใส่ชื่อ 1-30 ตัวอักษร';
  end if;
  select * into s from sessions
   where pin = trim(p_pin) and status <> 'ended' order by created_at desc limit 1;
  if s.id is null then raise exception 'ไม่พบห้องเกมนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  if (select count(*) from players where session_id = s.id) >= 300 then
    raise exception 'ห้องนี้เต็มแล้ว';
  end if;
  if exists (select 1 from players where session_id = s.id and lower(nickname) = lower(v_name)) then
    raise exception 'ชื่อนี้มีคนใช้แล้ว ลองชื่ออื่น';
  end if;
  insert into players (session_id, nickname, avatar)
  values (s.id, v_name, case when p_avatar ~ '^[a-z0-9-]{1,30}$' then p_avatar end) returning * into p;
  return jsonb_build_object('player_id', p.id, 'token', p.token, 'session_id', s.id,
                            'nickname', p.nickname, 'avatar', p.avatar, 'title', s.title);
end $$;

create or replace function public.player_state(p_player uuid, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p players; s sessions; q jsonb; a answers; v_rank int; v_n int; r jsonb;
begin
  select * into p from players where id = p_player and token = p_token;
  if p.id is null then return jsonb_build_object('status', 'kicked'); end if;
  select * into s from sessions where id = p.session_id;

  r := jsonb_build_object('status', s.status, 'title', s.title, 'index', s.current_index,
                          'total', s.total_questions, 'nickname', p.nickname, 'avatar', p.avatar, 'score', p.score,
                          'cover_url', s.cover_url);
  if s.current_index >= 0 then
    q := s.questions -> s.current_index;
    select * into a from answers where player_id = p.id and question_index = s.current_index;
  end if;

  if s.status = 'question' then
    r := r || jsonb_build_object(
      'question', q ->> 'text', 'image_url', q ->> 'image_url', 'choices', q -> 'choices',
      'colors', q -> 'colors', 'images', q -> 'images', 'time', (q ->> 'time')::int,
      'remaining', greatest(0, extract(epoch from s.question_ends_at - now())),
      'answered', a.id is not null, 'my_choice', a.choice);
  elsif s.status in ('reveal', 'ended') then
    select count(*) + 1 into v_rank from players where session_id = s.id and score > p.score;
    select count(*) into v_n from players where session_id = s.id;
    r := r || jsonb_build_object('rank', v_rank, 'players', v_n);
    if s.status = 'reveal' then
      r := r || jsonb_build_object(
        'question', q ->> 'text', 'choices', q -> 'choices', 'correct', (q ->> 'correct')::int,
        'colors', q -> 'colors', 'images', q -> 'images',
        'answered', a.id is not null, 'my_choice', a.choice,
        'is_correct', coalesce(a.is_correct, false), 'points', p.last_points);
    end if;
  end if;
  return r;
end $$;

-- ส่งคำตอบ: ถูกได้ 500-1000 คะแนน ตอบเร็วยิ่งได้มาก
create or replace function public.submit_answer(p_player uuid, p_token uuid, p_choice int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p players; s sessions; q jsonb; v_correct boolean; v_frac numeric; v_points int; v_id bigint;
begin
  select * into p from players where id = p_player and token = p_token;
  if p.id is null then raise exception 'ไม่พบผู้เล่น'; end if;
  select * into s from sessions where id = p.session_id;
  if s.status <> 'question' then raise exception 'หมดเวลาตอบข้อนี้แล้ว'; end if;
  if now() > s.question_ends_at + interval '1 second' then raise exception 'หมดเวลาตอบข้อนี้แล้ว'; end if;

  q := s.questions -> s.current_index;
  if p_choice < 0 or p_choice >= jsonb_array_length(q -> 'choices') then
    raise exception 'ตัวเลือกไม่ถูกต้อง';
  end if;
  v_correct := p_choice = (q ->> 'correct')::int;
  v_frac := least(1, greatest(0,
              extract(epoch from now() - s.question_started_at) / (q ->> 'time')::numeric));
  v_points := case when v_correct then round(1000 * (1 - v_frac / 2))::int else 0 end;

  insert into answers (session_id, player_id, question_index, choice, is_correct, points)
  values (s.id, p.id, s.current_index, p_choice, v_correct, v_points)
  on conflict (player_id, question_index) do nothing
  returning id into v_id;
  if v_id is null then raise exception 'ส่งคำตอบข้อนี้ไปแล้ว'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- จัดการรายชื่อผู้ดูแลระบบ (เฉพาะผู้ดูแล)
create or replace function public.list_admins()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  return coalesce((select jsonb_agg(email order by email) from app_admins), '[]'::jsonb);
end $$;

create or replace function public.add_admin(p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v text := lower(trim(coalesce(p_email, '')));
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  if v !~ ('^[^@\s]+@' || replace(lower((select allowed_domain from app_config where id = 1)), '.', '\.') || '$') then
    raise exception 'ต้องเป็นอีเมล @%', (select allowed_domain from app_config where id = 1);
  end if;
  insert into app_admins (email, added_by) values (v, lower(auth.jwt() ->> 'email')) on conflict do nothing;
  return public.list_admins();
end $$;

create or replace function public.remove_admin(p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  if (select count(*) from app_admins) <= 1 then raise exception 'ต้องมีผู้ดูแลระบบอย่างน้อย 1 คน'; end if;
  delete from app_admins where email = lower(trim(p_email));
  return public.list_admins();
end $$;

-- ใช้กับ Apps Script กันโปรเจกต์ถูกพัก
create or replace function public.ping()
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'quizzes', (select count(*) from quizzes), 'at', now())
$$;

-- สิทธิ์เรียกฟังก์ชัน
revoke execute on function public.save_quiz(uuid, text, text, text, jsonb, text, boolean),
                           public.list_admins(), public.add_admin(text), public.remove_admin(text),
                           public.duplicate_quiz(uuid), public.create_session(uuid),
                           public.host_next(uuid), public.host_reveal(uuid),
                           public.host_end(uuid), public.host_kick(uuid)
  from public, anon;
grant execute on function public.save_quiz(uuid, text, text, text, jsonb, text, boolean),
                          public.list_admins(), public.add_admin(text), public.remove_admin(text), public.is_admin(),
                          public.duplicate_quiz(uuid), public.create_session(uuid),
                          public.host_next(uuid), public.host_reveal(uuid),
                          public.host_end(uuid), public.host_kick(uuid)
  to authenticated;
grant execute on function public.join_game(text, text, text), public.player_state(uuid, uuid),
                          public.submit_answer(uuid, uuid, int), public.ping(), public.is_staff()
  to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Realtime: หน้าจอใหญ่ฟังคนเข้าห้อง / คนตอบ / คะแนน
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'players') then
    alter publication supabase_realtime add table public.players;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'answers') then
    alter publication supabase_realtime add table public.answers;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 6) ที่เก็บรูปประกอบคำถาม
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('quiz-images', 'quiz-images', true)
on conflict (id) do nothing;

drop policy if exists quiz_images_upload on storage.objects;
create policy quiz_images_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'quiz-images' and public.is_staff()
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists quiz_images_delete on storage.objects;
create policy quiz_images_delete on storage.objects for delete to authenticated
  using (bucket_id = 'quiz-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- 7) v5: แบบทดสอบ Pre-test / Post-test
--    รอบอบรม (trainings) ผูกกับชุดคำถาม 1 ชุด มี Pre และ Post เปิด/ปิดแยกกัน
--    ผู้ทำไม่ต้องล็อกอิน ระบุตัวด้วย รหัสพนักงาน + ชื่อ + แผนก
-- =====================================================================
create table if not exists public.departments (
  name text primary key check (char_length(name) between 1 and 120),
  sort int not null default 0
);

create table if not exists public.trainings (
  id          uuid primary key default gen_random_uuid(),
  quiz_id     uuid references public.quizzes(id) on delete set null,
  owner_id    uuid not null default auth.uid(),
  owner_email text not null default coalesce(auth.jwt() ->> 'email', ''),
  title       text not null check (char_length(title) between 1 and 200),
  code        text not null unique,
  pass_percent int not null default 80 check (pass_percent between 0 and 100),
  pre_open    boolean not null default false,
  post_open   boolean not null default false,
  questions   jsonb not null,           -- สำเนาคำถาม ณ ตอนสร้างรอบ (มีเฉลย)
  total       int not null,
  cover_url   text,
  created_at  timestamptz not null default now()
);

create table if not exists public.test_submissions (
  id           bigserial primary key,
  training_id  uuid not null references public.trainings(id) on delete cascade,
  phase        text not null check (phase in ('pre', 'post')),
  emp_id       text not null check (char_length(emp_id) between 1 and 30),
  full_name    text not null check (char_length(full_name) between 1 and 120),
  department   text not null default '',
  answers      jsonb not null,          -- ตัวเลือกที่ตอบ เรียงตามข้อ
  score        int not null,
  total        int not null,
  submitted_at timestamptz not null default now(),
  unique (training_id, phase, emp_id)
);
-- v6: แผนกที่ใช้ในแต่ละรอบ (null = ทุกแผนกจากรายชื่อหลัก)
alter table public.trainings add column if not exists departments jsonb;
create index if not exists test_submissions_training_idx on public.test_submissions (training_id, phase);

alter table public.departments      enable row level security;
alter table public.trainings        enable row level security;
alter table public.test_submissions enable row level security;
revoke all on public.departments, public.trainings, public.test_submissions from anon;
revoke all on public.departments from authenticated;
grant select, update, delete on public.trainings to authenticated;
grant select, delete on public.test_submissions to authenticated;

drop policy if exists trainings_owner on public.trainings;
create policy trainings_owner on public.trainings for select to authenticated
  using (owner_id = auth.uid() or public.is_admin());
drop policy if exists trainings_owner_upd on public.trainings;
create policy trainings_owner_upd on public.trainings for update to authenticated
  using (owner_id = auth.uid() or public.is_admin()) with check (owner_id = auth.uid() or public.is_admin());
drop policy if exists trainings_owner_del on public.trainings;
create policy trainings_owner_del on public.trainings for delete to authenticated
  using (owner_id = auth.uid() or public.is_admin());

drop policy if exists submissions_owner on public.test_submissions;
create policy submissions_owner on public.test_submissions for select to authenticated
  using (exists (select 1 from public.trainings t where t.id = training_id));
drop policy if exists submissions_owner_del on public.test_submissions;
create policy submissions_owner_del on public.test_submissions for delete to authenticated
  using (exists (select 1 from public.trainings t where t.id = training_id));

-- รายชื่อแผนก (ทุกคนอ่านได้ / ผู้ดูแลแก้ได้)
create or replace function public.list_departments()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(name order by sort, name), '[]'::jsonb) from departments
$$;
create or replace function public.set_departments(p_names jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'เฉพาะผู้ดูแลระบบ'; end if;
  delete from departments where true;   -- Supabase บังคับให้ DELETE มี WHERE
  insert into departments (name, sort)
  select distinct on (trim(n)) trim(n), min(ord) over (partition by trim(n))
    from jsonb_array_elements_text(coalesce(p_names, '[]'::jsonb)) with ordinality as t(n, ord)
   where trim(n) <> '';
  return public.list_departments();
end $$;

-- สร้างรอบอบรมจากชุดคำถาม (สิทธิ์เหมือนการเปิดห้องเกม)
create or replace function public.create_training(p_quiz_id uuid, p_title text, p_pass int default 80)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quiz quizzes; v_qs jsonb; v_n int; v_code text; v_id uuid; i int := 0;
begin
  if not public.is_staff() then raise exception 'ต้องเข้าสู่ระบบด้วยอีเมลบริษัท'; end if;
  select * into v_quiz from quizzes where id = p_quiz_id;
  if v_quiz.id is null then raise exception 'ไม่พบชุดคำถาม'; end if;
  if not (v_quiz.owner_id = auth.uid() or v_quiz.shared or public.is_admin()) then
    raise exception 'ชุดคำถามนี้เป็นแบบส่วนตัว';
  end if;
  select jsonb_agg(jsonb_build_object(
           'text', text, 'image_url', image_url, 'choices', choices, 'correct', correct_index,
           'colors', colors, 'images', choice_images) order by position), count(*)
    into v_qs, v_n from questions where quiz_id = p_quiz_id;
  if v_n = 0 then raise exception 'ชุดคำถามนี้ยังไม่มีคำถาม'; end if;
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from trainings where code = v_code);
    i := i + 1; if i > 50 then raise exception 'สร้างรหัสไม่สำเร็จ ลองใหม่อีกครั้ง'; end if;
  end loop;
  insert into trainings (quiz_id, title, code, pass_percent, questions, total, cover_url)
  values (p_quiz_id, left(coalesce(nullif(trim(p_title), ''), v_quiz.title), 200), v_code,
          least(100, greatest(0, coalesce(p_pass, 80))), v_qs, v_n, v_quiz.cover_url)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code);
end $$;

-- ข้อมูลแบบทดสอบสำหรับผู้ทำ (ไม่มีเฉลย / ส่งคำถามเฉพาะตอนเปิดอยู่)
create or replace function public.test_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t trainings;
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้ ตรวจสอบรหัสอีกครั้ง'; end if;
  return jsonb_build_object(
    'title', t.title, 'cover_url', t.cover_url, 'total', t.total,
    'pre_open', t.pre_open, 'post_open', t.post_open, 'pass_percent', t.pass_percent,
    'departments', case when jsonb_typeof(t.departments) = 'array' then t.departments else public.list_departments() end,
    'questions', case when t.pre_open or t.post_open then
      (select jsonb_agg(jsonb_build_object('text', q ->> 'text', 'image_url', q ->> 'image_url',
              'choices', q -> 'choices', 'colors', q -> 'colors', 'images', q -> 'images') order by o)
         from jsonb_array_elements(t.questions) with ordinality as x(q, o)) end);
end $$;

create or replace function public.submit_test(
  p_code text, p_phase text, p_emp_id text, p_name text, p_dept text, p_answers jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare t trainings; v_score int := 0; i int; v_ans int; v_pre test_submissions;
        v_emp text := upper(trim(coalesce(p_emp_id, ''))); v_name text := trim(coalesce(p_name, ''));
begin
  select * into t from trainings where code = trim(p_code);
  if t.id is null then raise exception 'ไม่พบแบบทดสอบนี้'; end if;
  if p_phase not in ('pre', 'post') then raise exception 'ระบุ Pre หรือ Post'; end if;
  if (p_phase = 'pre' and not t.pre_open) or (p_phase = 'post' and not t.post_open) then
    raise exception 'แบบทดสอบ %-test ปิดรับแล้ว', initcap(p_phase);
  end if;
  if v_emp = '' or v_name = '' then raise exception 'กรุณากรอกรหัสพนักงานและชื่อ-สกุล'; end if;
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> t.total then
    raise exception 'กรุณาตอบให้ครบทุกข้อ';
  end if;
  for i in 0 .. t.total - 1 loop
    if jsonb_typeof(p_answers -> i) <> 'number' then raise exception 'กรุณาตอบให้ครบทุกข้อ'; end if;
    v_ans := (p_answers ->> i)::int;
    if v_ans = (t.questions -> i ->> 'correct')::int then v_score := v_score + 1; end if;
  end loop;
  begin
    insert into test_submissions (training_id, phase, emp_id, full_name, department, answers, score, total)
    values (t.id, p_phase, v_emp, left(v_name, 120), left(trim(coalesce(p_dept, '')), 120), p_answers, v_score, t.total);
  exception when unique_violation then
    raise exception 'รหัสพนักงาน % ส่ง %-test ของรอบนี้ไปแล้ว', v_emp, initcap(p_phase);
  end;
  if p_phase = 'pre' then return jsonb_build_object('ok', true, 'phase', 'pre'); end if;
  select * into v_pre from test_submissions where training_id = t.id and phase = 'pre' and emp_id = v_emp;
  return jsonb_build_object('ok', true, 'phase', 'post', 'score', v_score, 'total', t.total,
    'percent', round(100.0 * v_score / t.total), 'pass', 100.0 * v_score / t.total >= t.pass_percent,
    'pass_percent', t.pass_percent, 'pre_score', v_pre.score,
    'correct', (select jsonb_agg((q ->> 'correct')::int order by o) from jsonb_array_elements(t.questions) with ordinality x(q, o)));
end $$;

revoke execute on function public.set_departments(jsonb), public.create_training(uuid, text, int) from public, anon;
grant execute on function public.set_departments(jsonb), public.create_training(uuid, text, int) to authenticated;
grant execute on function public.list_departments(), public.test_info(text),
                          public.submit_test(text, text, text, text, text, jsonb) to anon, authenticated;
