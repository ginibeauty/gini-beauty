-- =====================================================================
-- 지니뷰티 DB 보안 개편 2단계: 관리자(로그인한 사용자) 전용 정책 추가
-- 기존 고객용 정책은 그대로 두고 "추가만" 한다 (3단계 03_lockdown.sql 에서 기존 정책 삭제).
--
-- 사용법: ADMIN_EMAIL_1, ADMIN_EMAIL_2 를 실제 관리자 이메일로 바꿔서 실행.
--   * 이메일은 공개 저장소에 올리지 않는다 (이 파일은 빈칸 양식만 보관)
--   * Supabase > Authentication > Users 에 만든 관리자 계정 이메일과 같아야 한다
--   * 관리자가 한 명이면 ADMIN_EMAIL_2 자리에 같은 이메일을 한 번 더 써도 된다
-- 삭제(delete) 정책은 만들지 않는다 → 관리자도 API로 예약을 삭제할 수 없다.
-- =====================================================================

create policy "admin select" on public.reservations
  for select to authenticated
  using ((auth.jwt() ->> 'email') in ('ADMIN_EMAIL_1', 'ADMIN_EMAIL_2'));

create policy "admin insert" on public.reservations
  for insert to authenticated
  with check ((auth.jwt() ->> 'email') in ('ADMIN_EMAIL_1', 'ADMIN_EMAIL_2'));

create policy "admin update" on public.reservations
  for update to authenticated
  using ((auth.jwt() ->> 'email') in ('ADMIN_EMAIL_1', 'ADMIN_EMAIL_2'))
  with check ((auth.jwt() ->> 'email') in ('ADMIN_EMAIL_1', 'ADMIN_EMAIL_2'));
