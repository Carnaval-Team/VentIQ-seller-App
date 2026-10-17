select c.conrelid::regclass::text as tabla,
       c.conname,
       c.confdeltype as codigo,
       case c.confdeltype::text
         when 'n' then 'SET NULL'
         when 'c' then 'CASCADE'
         when 'a' then 'NO ACTION'
         when 'r' then 'RESTRICT'
         when 'd' then 'SET DEFAULT'
         else c.confdeltype::text
       end as on_delete
from pg_constraint c
where c.contype = 'f'
  and c.confrelid = 'flow.turno'::regclass
order by 1, 2;