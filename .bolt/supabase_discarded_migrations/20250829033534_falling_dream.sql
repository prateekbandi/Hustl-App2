@@ .. @@
-CREATE OR REPLACE FUNCTION accept_task(p_task_id uuid, p_user_id uuid)
+CREATE OR REPLACE FUNCTION accept_task(uuid, uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 AS $$
 DECLARE
   task_record record;
+  p_task_id ALIAS FOR $1;
+  p_user_id ALIAS FOR $2;
 BEGIN
   -- Check if task exists and is available for acceptance