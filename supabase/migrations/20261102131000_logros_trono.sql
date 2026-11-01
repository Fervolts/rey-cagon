-- Logros secretos del TRONO (lib/trono_vivo.dart): la mosca, el pujo eterno, el golpe de estado,
-- el insomnio de las 3 am y el filósofo. Se amplía la lista de claves válidas; las de antes siguen igual.

alter table public.logros drop constraint if exists logros_clave_valida;

alter table public.logros add constraint logros_clave_valida check (clave in (
  'psst_meon', 'psst_pulcro', 'psst_todas', 'corona', 'placer_lado',
  'trono_mosca', 'trono_pujo', 'trono_golpe', 'trono_desvelo', 'trono_filosofo'
));
