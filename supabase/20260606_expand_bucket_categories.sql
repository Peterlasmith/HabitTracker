alter table public.bucket_items
    drop constraint if exists bucket_items_category_check;

alter table public.bucket_items
    add constraint bucket_items_category_check
    check (category in ('travel', 'adventure', 'skills', 'experiences', 'milestones', 'giving', 'other'));
