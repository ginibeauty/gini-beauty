-- =====================================================================
-- 지니뷰티 DB 보안 개편 3단계: 테이블 잠금
-- 고객용(anon) 열쇠로 reservations 테이블을 직접 읽고/쓰는 정책을 삭제한다.
-- 이후 고객은 01_customer_functions.sql 의 함수로만, 관리자는 로그인 후에만 접근 가능.
-- 반드시 관리자 페이지 로그인이 실제로 동작하는 것을 확인한 뒤에 실행할 것.
--
-- [되돌리기] 문제가 생기면 아래 3줄을 실행하면 이전(개방) 상태로 복구된다.
--   create policy "public insert" on public.reservations for insert to anon with check (true);
--   create policy "public select" on public.reservations for select to anon using (true);
--   create policy "public update" on public.reservations for update to anon using (true) with check (true);
-- =====================================================================

drop policy if exists "public insert" on public.reservations;
drop policy if exists "public select" on public.reservations;
drop policy if exists "public update" on public.reservations;
