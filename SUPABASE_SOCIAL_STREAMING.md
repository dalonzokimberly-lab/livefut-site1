# LiveFut TV - Collegamento social streaming

Questa configurazione serve per collegare i canali social del broadcaster dallo studio LiveFut.

## 1. SQL

Esegui in Supabase SQL Editor:

```text
supabase_livefut_online_schema.sql
```

Il file crea anche:

- `broadcaster_social_accounts`
- `broadcast_destinations`
- `social_oauth_states`
- `broadcaster_social_tokens`

## 2. Edge Functions

Deploy delle funzioni:

```bash
supabase functions deploy social-oauth-start
supabase functions deploy social-oauth-callback
```

## 3. Secrets Supabase

Imposta questi secrets:

```bash
supabase secrets set SITE_URL=https://livefut-site1.vercel.app
supabase secrets set SOCIAL_OAUTH_CALLBACK_URL=https://obiiemjaxmgqeavrkxdc.functions.supabase.co/social-oauth-callback

supabase secrets set YOUTUBE_CLIENT_ID=...
supabase secrets set YOUTUBE_CLIENT_SECRET=...

supabase secrets set FACEBOOK_CLIENT_ID=...
supabase secrets set FACEBOOK_CLIENT_SECRET=...

supabase secrets set TWITCH_CLIENT_ID=...
supabase secrets set TWITCH_CLIENT_SECRET=...
```

`SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` sono disponibili nelle Edge Functions del progetto Supabase.

## 4. Callback provider

Questa callback è diversa da quella usata per il login Supabase Auth.

Per collegare i canali streaming aggiungi nei provider OAuth:

```text
https://obiiemjaxmgqeavrkxdc.functions.supabase.co/social-oauth-callback
```

La callback login Supabase resta:

```text
https://obiiemjaxmgqeavrkxdc.supabase.co/auth/v1/callback
```

## 5. Test

1. Apri `studio.html?id=...`
2. Vai su `Destinazioni diretta`
3. Clicca `Collega account`
4. Autorizza il provider
5. Torna allo studio
6. Il provider deve risultare disponibile e selezionabile

## 6. Nota produzione

I token sono salvati in una tabella non accessibile dal frontend. Per una produzione avanzata si può migrare il salvataggio token su Supabase Vault.
