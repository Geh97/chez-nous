# Chez nous

Appli web pour un couple ou une famille : rappels les uns aux autres, agenda commun, tâches, moments ensemble.
Chaque personne qui s'inscrit peut créer son espace privé (couple : 2 personnes, famille : 6) et y inviter d'autres personnes par e-mail.
Cible : deux iPhone, installée depuis Safari sur l'écran d'accueil. Interface en français.

## Fichiers

- `index.html` : toute l'appli (HTML, CSS, JavaScript pur, sans build ni framework).
- `schema.sql` : schéma Supabase à exécuter une fois dans le SQL Editor.
- `apple-touch-icon.png` : icône d'écran d'accueil iOS (180 x 180).

## Lancer et déployer

- En local : servir le dossier en statique (`npx serve .` ou `python3 -m http.server`).
- En ligne : GitHub Pages, dépôt public `Geh97/chez-nous`, branche `main`, adresse https://geh97.github.io/chez-nous/. Redéployer = `git push`.

## Backend : Supabase

- URL et clé publishable sont en constantes dans `index.html` (`SB_URL`, `SB_KEY`). La clé publishable peut rester dans le code client. Ne jamais y mettre la clé secret / service_role.
- supabase-js v2 est chargé par CDN (jsdelivr), global `window.supabase`.
- Authentification : e-mail + mot de passe, avec « Confirm email » activé (choix de l'utilisateur). Le lien de confirmation renvoie vers la Site URL, à régler avant de créer les comptes. Les inscriptions restent ouvertes (un espace par personne qui s'inscrit). L'inscription passe `emailRedirectTo` = adresse de l'appli ; `https://geh97.github.io/chez-nous/**` doit être dans les Redirect URLs.
- Tables : `spaces (id, kind couple|famille)`, `members (user_id pk, space_id)` (un seul espace par compte), `invites (space_id, email)`, `docs (space_id, coll, id, data jsonb, updated_at)`, clé primaire `(space_id, coll, id)`.
- RLS : chacun ne voit que son espace (`space_id = my_space()`). Les écritures sensibles passent par des RPC `security definer` : `create_space(p_kind)`, `invite(p_email)`, `my_invites()`, `accept_invite(sid)`. Une invitation n'est acceptée que pour l'e-mail confirmé du compte connecté. Capacité : 2 (couple), 6 (famille), invitations en attente comprises.
- Temps réel : abonnement `postgres_changes` sur `docs` (filtré côté client sur `space_id`, car les DELETE ne sont pas filtrés par RLS), plus rechargement complet au retour au premier plan (`visibilitychange`).

## Modèle de données (champ `data`)

- `people/<uid>` : `{ name, color, joinedAt }`, un document par personne, clé = id Supabase. Chacun écrit le sien. Toutes les références à une personne (`from`, `to`, `who`, `assignee`, `by`, `doneBy`) sont des uid.
- `reminders` : `{ from, to, text, due, createdAt, done, doneAt }`.
- `events` : `{ kind, title, date, allDay, start, end, who, by, createdAt }`.
  - `kind: "event"` : événement d'agenda, `who` vaut un uid ou `both` (« Nous deux » / « Tout le monde »).
  - `kind: "couple"` : moment à deux (ou en famille ; n'importe quel autre membre peut répondre), avec `status` (`proposed`, `accepted`, `declined`), `by` (qui propose) et `note`.
- `tasks` : `{ title, assignee (uid|both), category (maison|perso|couple), due, recurrence (none|daily|weekly|monthly), needsValidation, status (todo|pending|done), by, doneBy, doneAt, lastDoneAt, createdAt }`.
  - `pending` = fait, en attente de validation par un autre membre. Une tâche récurrente terminée repasse en `todo` avec l'échéance suivante.
- Dates en `YYYY-MM-DD`, heures en `HH:MM`, horodatages en millisecondes.

## Structure du code (`index.html`)

- `S` : état global. `store` : accès aux données (`put`, `del`, mise à jour optimiste puis écriture Supabase). Helpers personnes : `couple()`, `ids()`, `others()`, `pName()` (prénom de l'autre en couple), `P(uid)`.
- `render()` choisit l'écran : connexion, invitation reçue (`vInvited`) ou création d'espace (`vCreate`), profil (`vProfile`), puis l'appli.
- Vues : `vFrigo` (rappels en notes aimantées + programme du jour), `vAgenda`, `vTaches`, `vDeux`.
- Panneaux de saisie : `fReminder`, `fEvent`, `fDeux`, `fTask`, `fSettings` (profil, membres, invitations), `fInvite`, `fAdd`.
- Actions : objet `A`, déclenchées par délégation sur les attributs `data-act`. Choix exclusifs via `data-seg`.
- Tout texte saisi passe par `esc()` avant d'être inséré en HTML.

## Choix de conception

- Pas de notifications push : les rappels se voient à l'ouverture de l'appli.
- Agenda interne, sans synchronisation avec Google Calendar ou iCloud.
- Style chaleureux et ludique, une couleur par personne (variables CSS `--c` / `--c2`), dégradé des deux premières couleurs pour ce qui concerne tout le monde. Les couleurs déjà prises sont grisées. Pas d'emojis dans l'interface.
- Polices : Bricolage Grotesque (interface) et Caveat (texte des notes), via Google Fonts.
- Thème clair et sombre automatiques, zones de sécurité iOS gérées (`env(safe-area-inset-*)`).

## État

Première version, non testée sur un vrai iPhone ni contre le projet Supabase réel.
