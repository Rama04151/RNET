-- RNET Store: nested categories and GitHub-hosted thumbnails
alter table public.categories add column if not exists parent_id uuid references public.categories(id) on delete set null;
alter table public.categories add column if not exists image_path text not null default '';
alter table public.products add column if not exists image_path text not null default '';
create index if not exists categories_parent_active_idx on public.categories(parent_id,is_active);
