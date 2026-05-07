# Accrediti squadra - flusso super user

Le richieste inviate da `dashboard.html` finiscono nella tabella Supabase:

`public.accreditation_requests`

Ruoli ammessi:

- `presidente`
- `vice_presidente`
- `segretario`
- `amministratore`
- `delegato_dirette`

Stati ammessi:

- `pending`
- `approved`
- `rejected`

## Come approvare manualmente

In Supabase vai in:

Table Editor -> `accreditation_requests`

Apri la riga richiesta e modifica:

- `status`: `approved`
- `reviewed_at`: data/ora corrente
- `review_notes`: eventuale nota

Per rifiutare:

- `status`: `rejected`
- `review_notes`: motivo del rifiuto

Nota: la richiesta non assegna automaticamente poteri. Serve una seconda fase in cui, dopo l'approvazione, colleghiamo i permessi effettivi al profilo utente o alla squadra.
