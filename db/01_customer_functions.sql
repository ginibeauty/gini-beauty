-- =====================================================================
-- 지니뷰티 DB 보안 개편 1단계: 고객용 함수 (기존 기능에 영향 없음, 추가만 함)
-- Supabase 대시보드 > SQL Editor 에서 전체를 붙여넣고 Run
-- 고객 페이지는 테이블을 직접 읽지 않고 아래 함수(창구)만 사용하게 된다.
-- 모든 함수는 security definer 로 동작하며, 조회/수정/취소는
-- "예약 코드 + 연락처"가 모두 일치해야만 허용한다. 5일 규칙도 서버에서 강제한다.
-- =====================================================================

-- 1) 예약 등록 : 코드는 서버가 발급해서 돌려준다
create or replace function public.create_reservation(
  p_name text, p_phone text, p_service text, p_date text
) returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_code text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_try int := 0;
begin
  if coalesce(trim(p_name), '') = '' or char_length(p_name) > 50 then
    raise exception 'invalid name';
  end if;
  if char_length(v_digits) not between 10 and 11 then
    raise exception 'invalid phone';
  end if;
  if coalesce(p_service, '') not in ('눈썹문신', '피부미용', '염색', '기타 상담') then
    raise exception 'invalid service';
  end if;
  if p_date::date < v_today then
    raise exception 'invalid date';
  end if;

  loop
    v_code := to_char(v_today, 'YYYYMMDD') || (1000 + floor(random() * 9000))::int::text;
    exit when not exists (select 1 from reservations x where x.code = v_code);
    v_try := v_try + 1;
    if v_try > 20 then raise exception 'code generation failed'; end if;
  end loop;

  insert into reservations (code, name, phone, service, date, status)
  values (v_code, trim(p_name), p_phone, p_service, p_date::date, 'pending');

  return v_code;
end $$;

-- 2) 예약 조회 : 코드 + 연락처가 모두 맞아야 반환 (cancel_token 은 제외)
create or replace function public.get_reservation(p_code text, p_phone text)
returns jsonb
language sql security definer set search_path = public stable
as $$
  select to_jsonb(r) - 'cancel_token'
  from reservations r
  where r.code = p_code
    and length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 10
    and regexp_replace(coalesce(r.phone, ''), '\D', '', 'g') = regexp_replace(p_phone, '\D', '', 'g')
  limit 1;
$$;

-- 3) 연락처로 코드 찾기 : 코드/시술/날짜/상태만 반환 (이름·연락처 제외)
create or replace function public.find_reservations_by_phone(p_phone text)
returns jsonb
language sql security definer set search_path = public stable
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('code', r.code, 'service', r.service, 'date', r.date, 'status', r.status)
      order by r.created_at desc
    ),
    '[]'::jsonb
  )
  from reservations r
  where length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 10
    and regexp_replace(coalesce(r.phone, ''), '\D', '', 'g') = regexp_replace(p_phone, '\D', '', 'g');
$$;

-- 4) 예약 수정 : 예약 대기 상태 + 시술일 5일 전까지만 (기존/새 날짜 모두 검사)
create or replace function public.update_reservation(
  p_code text, p_phone text, p_name text, p_new_phone text, p_service text, p_date text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r reservations%rowtype;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_digits text := regexp_replace(coalesce(p_new_phone, ''), '\D', '', 'g');
begin
  select * into r from reservations x
   where x.code = p_code
     and length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 10
     and regexp_replace(coalesce(x.phone, ''), '\D', '', 'g') = regexp_replace(p_phone, '\D', '', 'g');
  if not found then raise exception 'not found'; end if;
  if coalesce(r.status, 'pending') <> 'pending' then raise exception 'not editable'; end if;
  if r.date::date < v_today + 5 then raise exception 'too late'; end if;

  if coalesce(trim(p_name), '') = '' or char_length(p_name) > 50 then
    raise exception 'invalid name';
  end if;
  if char_length(v_digits) not between 10 and 11 then
    raise exception 'invalid phone';
  end if;
  if coalesce(p_service, '') not in ('눈썹문신', '피부미용', '염색', '기타 상담') then
    raise exception 'invalid service';
  end if;
  if p_date::date < v_today + 5 then raise exception 'invalid date'; end if;

  update reservations x
     set name = trim(p_name), phone = p_new_phone, service = p_service, date = p_date::date
   where x.code = p_code
   returning * into r;

  return to_jsonb(r) - 'cancel_token';
end $$;

-- 5) 취소 요청 : 예약 대기 상태 + 시술일 5일 전까지만 (최종 취소는 관리자가 승인)
create or replace function public.request_cancel_reservation(p_code text, p_phone text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r reservations%rowtype;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  select * into r from reservations x
   where x.code = p_code
     and length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 10
     and regexp_replace(coalesce(x.phone, ''), '\D', '', 'g') = regexp_replace(p_phone, '\D', '', 'g');
  if not found then raise exception 'not found'; end if;
  if coalesce(r.status, 'pending') <> 'pending' then raise exception 'not cancellable'; end if;
  if r.date::date < v_today + 5 then raise exception 'too late'; end if;

  update reservations x set status = 'cancel_requested' where x.code = p_code returning * into r;

  return to_jsonb(r) - 'cancel_token';
end $$;

-- 실행 권한: 로그인 안 한 고객(anon)과 관리자(authenticated)만 호출 가능
revoke all on function public.create_reservation(text, text, text, text) from public;
revoke all on function public.get_reservation(text, text) from public;
revoke all on function public.find_reservations_by_phone(text) from public;
revoke all on function public.update_reservation(text, text, text, text, text, text) from public;
revoke all on function public.request_cancel_reservation(text, text) from public;

grant execute on function public.create_reservation(text, text, text, text) to anon, authenticated;
grant execute on function public.get_reservation(text, text) to anon, authenticated;
grant execute on function public.find_reservations_by_phone(text) to anon, authenticated;
grant execute on function public.update_reservation(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.request_cancel_reservation(text, text) to anon, authenticated;
