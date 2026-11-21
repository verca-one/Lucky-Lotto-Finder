-- store_photos_delete.sql — 관리자 사진 삭제 함수만 (store_photos.sql 을 이미 실행했다면 이것만 실행)
CREATE OR REPLACE FUNCTION delete_store_photo(p_id uuid, p_key text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM store_photo_admin WHERE key = p_key) THEN
    RAISE EXCEPTION '승인 키가 맞지 않습니다';
  END IF;
  DELETE FROM store_photos WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION delete_store_photo(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION delete_store_photo(uuid, text) TO anon, authenticated;
SELECT 'delete_store_photo' AS check, (to_regprocedure('delete_store_photo(uuid,text)') IS NOT NULL)::text AS value;
