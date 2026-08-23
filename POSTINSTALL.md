## PB Translation Hub wurde installiert

Die App ist erreichbar unter $CLOUDRON-APP-ORIGIN.

**Admin-Login:** Falls beim Install kein `ADMIN_USERNAME`/`ADMIN_PASSWORD` gesetzt wurde, hat die
App automatisch einen Admin-Account mit einem zufälligen Passwort angelegt. Zu finden in den
App-Logs (`cloudron logs --app <subdomain>`, Zeile "No ADMIN_USERNAME/ADMIN_PASSWORD set —
generated an admin account") oder per `cloudron exec --app <subdomain> -- cat
/app/data/.admin_credentials`. Nach dem ersten Login unbedingt das Passwort ändern.

Nach der Erstinstallation müssen einmalig Datenbank und Übersetzungsdateien importiert werden —
Schritt-für-Schritt-Anleitung: [CLOUDRON_DEPLOYMENT.md](https://github.com/nodedropweb/pb_translation_hub-cloudron/blob/master/CLOUDRON_DEPLOYMENT.md#3-post-install-importing-existing-data)
