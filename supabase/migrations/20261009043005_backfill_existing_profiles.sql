insert into public.profiles(id,display_name) select id,left(coalesce(raw_user_meta_data->>'display_name',''),120) from auth.users on conflict(id) do nothing;
notify pgrst, 'reload schema';
