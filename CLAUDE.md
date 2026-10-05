# Chez nous

Appli web à deux (un couple) : rappels l'un à l'autre, agenda commun, tâches, moments à deux.
Cible : deux iPhone, installée depuis Safari sur l'écran d'accueil. Interface en français.

## Fichiers

- `index.html` : toute l'appli (HTML, CSS, JavaScript pur, sans build ni framework).
- `schema.sql` : schéma Supabase à exécuter une fois dans le SQL Editor.
- `apple-touch-icon.png` : icône d'écran d'accueil iOS (180 x 180).

## Lancer et déployer

- En local : servir le dossier en statique (`npx serve .` ou `python3 -m http.server`).
- En ligne : n'importe quel hébergeur statique (Netlify, Vercel, Cloudflare Pages). Aucun build.

## Backend : Supabase

- URL et clé publishable sont en constantes dans `index.html` (`SB_URL`, `SB_KEY`). La clé publishable peut rester dans le code client. Ne jamais y mettre la clé secret / service_role.
- supabase-js v2 est chargé par CDN (jsdelivr), global `window.supabase`.
- Authentification : e-mail + mot de passe, avec « Confirm email » activé (choix de l'utilisateur). Le lien de confirmation renvoie vers la Site URL, à régler avant de créer les comptes. Les inscriptions sont à fermer une fois les deux comptes créés.
- Table `members` : deux lignes maximum. La fonction RPC `join_home()` inscrit l'utilisateur connecté s'il reste une place et renvoie `false` sinon.
- Table `docs (coll, id, data jsonb, updated_at)`, clé primaire `(coll, id)`. RLS : lecture et écriture réservées aux membres (`is_member()`).
- Temps réel : abonnement `postgres_changes` sur `docs`, plus rechargement complet au retour au premier plan (`visibilitychange`).

## Modèle de données (champ `data`)

- `config/main` : `{ people: { p1: {name, color, uid}, p2: {name, color, uid} } }`. `uid` = id Supabase de la personne, sert à reconnaître qui est connecté.
- `reminders` : `{ from, to, text, due, createdAt, done, doneAt }` (`from` / `to` valent `p1` ou `p2`).
- `events` : `{ kind, title, date, allDay, start, end, who, by, createdAt }`.
  - `kind: "event"` : événement d'agenda, `who` vaut `p1`, `p2` ou `both`.
  - `kind: "couple"` : moment à deux, avec `status` (`proposed`, `accepted`, `declined`), `by` (qui propose) et `note`.
- `tasks` : `{ title, assignee (p1|p2|both), category (maison|perso|couple), due, recurrence (none|daily|weekly|monthly), needsValidation, status (todo|pending|done), by, doneBy, doneAt, lastDoneAt, createdAt }`.
  - `pending` = fait, en attente de validation par l'autre. Une tâche récurrente terminée repasse en `todo` avec l'échéance suivante.
- Dates en `YYYY-MM-DD`, heures en `HH:MM`, horodatages en millisecondes.

## Structure du code (`index.html`)

- `S` : état global. `store` : accès aux données (`put`, `del`, `putConfig`, mise à jour optimiste puis écriture Supabase).
- `render()` choisit l'écran : connexion, configuration initiale, « qui es-tu », puis l'appli.
- Vues : `vFrigo` (rappels en notes aimantées + programme du jour), `vAgenda`, `vTaches`, `vDeux`.
- Panneaux de saisie : `fReminder`, `fEvent`, `fDeux`, `fTask`, `fSettings`, `fAdd`.
- Actions : objet `A`, déclenchées par délégation sur les attributs `data-act`. Choix exclusifs via `data-seg`.
- Tout texte saisi passe par `esc()` avant d'être inséré en HTML.

## Choix de conception

- Pas de notifications push : les rappels se voient à l'ouverture de l'appli.
- Agenda interne, sans synchronisation avec Google Calendar ou iCloud.
- Style chaleureux et ludique, une couleur par personne (variables CSS `--c` / `--c2`), dégradé des deux couleurs pour ce qui concerne le couple. Pas d'emojis dans l'interface.
- Polices : Bricolage Grotesque (interface) et Caveat (texte des notes), via Google Fonts.
- Thème clair et sombre automatiques, zones de sécurité iOS gérées (`env(safe-area-inset-*)`).

## État

Première version, non testée sur un vrai iPhone ni contre le projet Supabase réel.
