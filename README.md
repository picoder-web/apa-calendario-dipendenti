# APA Calendario Dipendenti

![Versione](https://img.shields.io/badge/versione-1.0-informational)
![Licenza: MIT](https://img.shields.io/badge/Licenza-MIT-yellow.svg)
![Piattaforma](https://img.shields.io/badge/Piattaforma-Raspberry%20Pi%20OS%20%7C%20Ubuntu-blue)
![Shell](https://img.shields.io/badge/Shell-bash-green)

Trasforma un Raspberry Pi o un PC Ubuntu in un **display a schermo intero per il calendario dei dipendenti**: i dati vengono letti da un file **CSV** (ad esempio un foglio Google pubblicato sul web), disegnati in una tabella colorata e mostrati in Chromium sul **monitor primario**. L'applicazione parte da sola all'accesso al desktop, si controlla in continuazione e chiude tutto in modo pulito in caso di errore.

**Versione 1.0**

## Indice

- [Caratteristiche](#caratteristiche)
- [Requisiti](#requisiti)
- [Installazione rapida](#installazione-rapida)
- [Installazione manuale](#installazione-manuale)
- [Uso da terminale](#uso-da-terminale)
- [Come funziona](#come-funziona)
- [Formato del CSV](#formato-del-csv)
- [File installati](#file-installati)
- [Configurazione](#configurazione)
- [Log e debug](#log-e-debug)
- [Aggiornamenti e versioni](#aggiornamenti-e-versioni)
- [Disinstallazione](#disinstallazione)
- [Risoluzione dei problemi](#risoluzione-dei-problemi)
- [Note su privacy e sicurezza](#note-su-privacy-e-sicurezza)
- [Licenza](#licenza)

## Caratteristiche

- Installer interattivo con menu (installa, aggiorna, reinstalla da zero, disinstalla).
- Comando da terminale `apa-calendario-dipendenti` per avviare l'applicazione.
- Avvio automatico dopo l'accesso al desktop, con un'attesa configurabile e un terminale che mostra lo stato.
- Pagina a schermo intero sul **monitor primario**, con verifica della posizione della finestra (e correzione automatica tramite `xdotool` / `wmctrl`).
- Server locale che scarica il CSV al posto del browser (evita il blocco CORS) e usa l'ultima copia salvata se internet non è disponibile.
- Supervisione silenziosa ogni 2 minuti: se la finestra o il server si fermano, tutto viene chiuso e l'errore viene registrato.
- Chiusura pulita anche con **Ctrl+C**, con segnale di terminazione o chiudendo il terminale.
- Una sola copia alla volta in esecuzione (avvio automatico e comando da terminale non si sovrappongono).
- Due file di log: uno completo e uno solo con gli errori, con rotazione automatica.
- Console di debug nel browser e nei log (array ottenuto dal CSV, risposte del server, errori).
- L'installer riconosce se si tratta di una **nuova installazione o di un aggiornamento** e propone come predefiniti i valori inseriti la volta precedente.

## Requisiti

- **Sistema:** Raspberry Pi OS o Ubuntu (e derivate) con desktop grafico. È consigliata una sessione **X11**; con **Wayland** Chromium viene avviato in modalità X11 (XWayland) per poter posizionare la finestra.
- **Browser:** Chromium o Google Chrome.
  - Raspberry Pi OS: `sudo apt install chromium-browser` (oppure `chromium`)
  - Ubuntu: `sudo snap install chromium`
- **Programmi di supporto**, installati automaticamente dall'installer con `apt` se mancano (può chiedere la password di `sudo`): `python3`, `x11-xserver-utils` (`xrandr`), `xdotool`, `wmctrl`.
- **Connessione a internet** per scaricare il CSV.
- **Un foglio pubblicato come CSV** (vedi [Formato del CSV](#formato-del-csv)).

## Installazione rapida

Apri un terminale **con il tuo utente normale** (senza `sudo`) ed esegui:

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/picoder-web/apa-calendario-dipendenti/main/install.sh)"
```

L'installer scarica ed esegue lo script, poi ti guida con un menu e poche domande.

> - **Non usare `sudo`.** I file vengono installati nella tua home e Chromium non parte se eseguito come root.
> - Se `wget` non è installato: `sudo apt install wget`.
> - Prima di eseguire un comando scaricato da internet puoi leggerne il contenuto:
>   `wget -qO- https://raw.githubusercontent.com/picoder-web/apa-calendario-dipendenti/main/install.sh | less`
> - Per vedere solo le versioni senza modificare nulla:
>   `bash -c "$(wget -qO- https://raw.githubusercontent.com/picoder-web/apa-calendario-dipendenti/main/install.sh)" _ --versione`

### Il menu dell'installer

| Opzione | Cosa fa |
|---|---|
| **1) Installa** | Nuova installazione |
| **2) Reinstalla / Aggiorna** | Riscrive i file mantenendo i log; si usa anche per cambiare link o impostazioni |
| **3) Reinstalla da zero** | Rimuove tutto (compreso il profilo del browser) e reinstalla |
| **4) Disinstalla** | Rimuove tutti i file dell'applicazione |
| **5) Esci** | Non modifica nulla |

### Le domande dell'installer

Premendo INVIO si conferma il valore tra parentesi quadre (quello della volta precedente, oppure quello predefinito).

1. **Link del file CSV** da mostrare (deve iniziare con `http://` o `https://`).
2. **Ogni quanti secondi aggiornare i dati** (minimo 10, predefinito 300).
3. **Secondi di attesa dopo l'avvio del desktop** (predefinito 10).
4. **Avvio automatico** all'accesso al desktop (s/n).

## Installazione manuale

```bash
git clone https://github.com/picoder-web/apa-calendario-dipendenti.git
cd apa-calendario-dipendenti
chmod +x install.sh
./install.sh
```

Anche qui l'installer va eseguito con il tuo utente, **non con `sudo`**. Se per sbaglio usi `sudo ./install.sh`, l'installer si rilancia da solo con l'utente che ha usato `sudo`. Per vedere le versioni senza modificare nulla: `./install.sh --versione`.

## Uso da terminale

L'installer crea il comando **`apa-calendario-dipendenti`** (un collegamento in `~/.local/bin`). Se `~/.local/bin` non era nel `PATH`, l'installer lo aggiunge a `~/.bashrc`: **apri un nuovo terminale** (oppure esegui `source ~/.bashrc`) prima di usare il comando.

```bash
apa-calendario-dipendenti            # avvia il calendario (attende, poi apre Chromium)
apa-calendario-dipendenti --subito   # avvia senza l'attesa iniziale
apa-calendario-dipendenti --log      # segue in tempo reale il log completo (Ctrl+C per uscire)
apa-calendario-dipendenti --errori   # segue in tempo reale il log degli errori
apa-calendario-dipendenti --versione # mostra la versione
apa-calendario-dipendenti --aiuto    # elenco delle opzioni
```

- Il comando funziona **nel terminale in cui lo lanci**: lo stato viene mostrato lì e con **Ctrl+C** (o chiudendo il terminale) la finestra del calendario e il server locale vengono chiusi.
- Può girare **una sola copia alla volta**: se il calendario è già in esecuzione (per esempio avviato dall'avvio automatico), una seconda copia si ferma con un avviso senza toccare la prima.
- Se un'esecuzione precedente è stata interrotta in modo brusco (`kill -9`, spegnimento forzato) e ha lasciato processi aperti, al successivo avvio vengono chiusi automaticamente.

## Come funziona

```text
Foglio Google pubblicato come CSV
              │  scaricato da...
              ▼
   server.py  (solo su 127.0.0.1, porta libera)  ──▶  copia di riserva dati-cache.csv
              │  /calendario.html  e  /dati.csv
              ▼
   Chromium a schermo intero sul monitor primario
```

Il browser **non può leggere direttamente** il CSV di Google: il server di Google non invia l'intestazione `Access-Control-Allow-Origin`, quindi una pagina aperta dal browser riceve l'errore *"blocked by CORS policy"*. Per questo l'installer crea `server.py`, un piccolo server Python (solo libreria standard) che:

- serve la pagina `calendario.html`;
- scarica il CSV al posto del browser e lo passa alla pagina dallo stesso indirizzo (`/dati.csv`), seguendo i redirect di Google;
- se internet non è disponibile, usa l'**ultima copia salvata** (per 24 ore, configurabile). Se la copia manca o è troppo vecchia risponde 503 e la pagina resta su "Caricamento...";
- segnala quando la risposta è una pagina HTML invece di un CSV (tipicamente il foglio non è pubblicato sul web).

La pagina si ricarica da sola all'intervallo scelto e a ogni ricarico i dati vengono riscaricati.

Il calendario si apre sempre sul **monitor primario** indicato da `xrandr`. Se nessun monitor è primario viene usato il primo da sinistra e il fatto viene registrato nel log. Per cambiare il monitor primario: `xrandr --output NOME --primary`.

## Formato del CSV

Il foglio va pubblicato come CSV: in Google Fogli, *File → Condividi → Pubblica sul web*, scegli il foglio e il formato **Valori separati da virgola (.csv)**, poi copia il link.

La pagina si aspetta circa 30 righe e fino a 10 colonne (la numerazione delle righe parte da 1):

- **riga 1:** nella colonna B c'è il titolo/data, mostrato nell'intestazione in alto (in maiuscolo);
- **righe 2 e 18:** intestazioni dei due blocchi (testo grande, grassetto, fondo grigio); **righe 3 e 19:** sottointestazioni in corsivo;
- **righe 4–16** (primo blocco) e **righe 20–30** (secondo blocco): celle dei turni.

Parole chiave nelle celle dei turni (il confronto non distingue maiuscole e minuscole): se una cella contiene esattamente una di queste parole, viene colorata **tutta la colonna** di quel blocco:

| Parole | Colore |
|---|---|
| `assente`, `assenza`, `ass` | grigio |
| `malattia`, `malato`, `malata` | grigio |
| `stand-by`, `standby`, `stand by`, `stanby` | arancione |
| `emergenza`, `eme`, `118` | giallo |
| `notte` | verde acqua |
| `trasferimenti`, `trasf`, `tras` | verde |

Inoltre le celle scritte **tutte in maiuscolo** (che non iniziano con una cifra) vengono evidenziate in grassetto corsivo con fondo arancione chiaro.

## File installati

```text
~/apa-calendario-dipendenti/
├── apa-calendario-dipendenti.sh   # avvio, controllo e chiusura (con la configurazione in cima)
├── calendario.html                # la pagina che disegna la tabella
├── server.py                      # server locale: pagina + CSV
├── dati-cache.csv                 # ultima copia del CSV scaricato (creata a runtime)
├── profilo/                       # profilo di Chromium (cartella non nascosta: serve per lo snap)
└── logs/
    ├── calendario.log             # log completo
    └── error.log                  # solo errori
~/.local/bin/apa-calendario-dipendenti                   # comando da terminale (collegamento)
~/.config/autostart/apa-calendario-dipendenti.desktop    # avvio automatico (se scelto)
```

## Configurazione

Link CSV, intervallo di aggiornamento, attesa e avvio automatico si cambiano **rilanciando l'installer** (opzione 2). Le altre impostazioni sono variabili in cima a `apa-calendario-dipendenti.sh`:

| Variabile | Predefinito | Significato |
|---|---|---|
| `CSV_URL` | (scelto all'installazione) | Link del CSV scaricato dal server locale |
| `DELAY` | `10` | Secondi di attesa prima di iniziare |
| `TENTATIVI` / `PAUSA` | `5` / `3` | Tentativi (e secondi tra l'uno e l'altro) per rilevare i monitor |
| `BROWSER_FORZATO` | vuoto | Percorso di un browser specifico (vuoto = automatico) |
| `INTERVALLO_CONTROLLO` | `120` | Secondi tra un controllo completo e l'altro |
| `TIMEOUT_CSV` | `20` | Secondi massimi per scaricare il CSV |
| `COPIA_MAX_ORE` | `24` | Ore per cui si usa l'ultima copia se internet manca |
| `MAX_LOG_KB` | `5120` | Oltre questa dimensione i log vengono ruotati (copia `.old`) |

> Le modifiche manuali ad `apa-calendario-dipendenti.sh` e a `calendario.html` vengono **sovrascritte** da una reinstallazione: vengono mantenuti solo i valori che l'installer richiede.

## Log e debug

- **`calendario.log`** (completo) contiene l'avvio, il rilevamento dei monitor, i messaggi del server (ogni download con esito, byte, righe e tempi), i messaggi della console del browser, un controllo periodico ogni 2 minuti (silenzioso a terminale) e le chiusure.
- **`error.log`** contiene solo gli errori: download falliti, errori della console del browser (compreso un eventuale blocco CORS), finestra o server chiusi inaspettatamente, interruzioni.
- Ogni riga ha il formato `[AAAA-MM-GG hh:mm:ss] [LIVELLO] messaggio`. Per seguirli in tempo reale: `apa-calendario-dipendenti --log` e `apa-calendario-dipendenti --errori`.

La pagina scrive nella **console del browser** (si apre con `F12`) messaggi che iniziano con `[calendario]`: indirizzo della pagina, richiesta e risposta (stato HTTP, dati nuovi o copia salvata), numero di righe del CSV, **l'array ottenuto dal CSV** (come oggetto espandibile e in JSON) e il riepilogo del disegno (righe, parole chiave trovate, celle evidenziate). Lo script di avvio copia questi messaggi, insieme agli errori della console, sul terminale e nei log.

Il livello di dettaglio si imposta con la variabile `DEBUG` in `calendario.html`: `0` = nessun messaggio, `1` = riepilogo e array del CSV (predefinito), `2` = anche ogni cella evidenziata.

## Aggiornamenti e versioni

L'installer contiene un numero di versione (questa è la **1.0**) e lo confronta con quello già installato, mostrando:

- `NUOVA INSTALLAZIONE`;
- `AGGIORNAMENTO: da X a Y` (con l'elenco delle novità);
- `REINSTALLAZIONE` (stessa versione);
- un avviso se la versione installata è **più recente** di quella dell'installer, con richiesta di conferma.

Un suffisso come `-rc.1` conta come precedente alla versione finale (`1.1-rc.1` < `1.1`).

Per aggiornare, rilancia il [comando di installazione rapida](#installazione-rapida) e scegli l'opzione **2**: i valori che avevi inserito vengono proposti come predefiniti e ti basta premere INVIO. Le versioni sono pubblicate nella sezione **Releases** del repository; la release segnata come *Latest* è l'ultima stabile e il ramo `main` corrisponde a quella.

## Disinstallazione

Rilancia l'installer e scegli l'opzione **4**: vengono rimossi la cartella dell'applicazione (script, pagina, server, log e profilo del browser), il comando da terminale, l'avvio automatico e l'eventuale riga aggiunta a `~/.bashrc`. Per togliere solo l'avvio automatico, elimina `~/.config/autostart/apa-calendario-dipendenti.desktop`.

## Risoluzione dei problemi

| Problema | Cosa fare |
|---|---|
| `apa-calendario-dipendenti: command not found` | Apri un nuovo terminale oppure esegui `source ~/.bashrc`: serve se `~/.local/bin` è stato aggiunto al `PATH` durante l'installazione |
| "Il calendario è già in esecuzione" | È già aperto (per esempio dall'avvio automatico): non serve avviarlo di nuovo. Per fermarlo, chiudi il terminale in cui gira o premi Ctrl+C |
| La pagina resta su "Caricamento..." | Guarda `logs/error.log`: di solito il foglio non è pubblicato come CSV, il link è sbagliato o manca la connessione. Con internet assente il server usa l'ultima copia salvata, se esiste |
| Errore *"blocked by CORS policy"* | Succede se la pagina legge direttamente il CSV di Google. Con questa applicazione non dovrebbe comparire perché il CSV passa dal server locale: controlla che l'installazione sia completa (`server.py` presente) |
| La finestra si apre sul monitor sbagliato | Imposta il monitor primario con `xrandr --output NOME --primary`. Su Wayland il posizionamento è più difficile: prova una sessione X11 (su Raspberry Pi OS: `sudo raspi-config` → *Advanced Options* → *Wayland* → *X11*) |
| Chromium chiede una password (portachiavi) | Il browser viene già avviato con `--password-store=basic`; se compare ancora, controlla di non aver lanciato lo script con `sudo` |
| `Running as root without --no-sandbox` | Lo script è stato eseguito come root: lancialo con il tuo utente |
| Il browser si chiude subito all'avvio | Controlla le ultime righe riportate in `error.log` (contengono l'output del browser). Con lo snap, il profilo deve stare in una cartella non nascosta, come fa l'installer |
| `python3` / `xrandr` / `xdotool` non trovati | Installali con `sudo apt install python3 x11-xserver-utils xdotool wmctrl` |
| Il terminale all'avvio non si vede | Servono un terminale grafico (`gnome-terminal`, `lxterminal`, `xfce4-terminal`, `konsole` o `x-terminal-emulator`) e la sessione desktop attiva: l'avvio automatico parte all'accesso, non al boot della macchina |

## Note su privacy e sicurezza

- Il server locale ascolta **solo su `127.0.0.1`**: non è raggiungibile da altri computer della rete.
- Un foglio "pubblicato sul web" è accessibile da **chiunque abbia il link**, anche senza account. Non pubblicare in questo modo dati riservati e **non inserire in un repository pubblico il link del tuo foglio** (nemmeno come valore predefinito dell'installer).
- Il browser viene avviato con un profilo dedicato e separato da quello personale.
- I link e il testo inseriti nell'installer non possono contenere i caratteri `"` `\` `$` `` ` `` (e, per il link CSV, `<`, `>` e spazi), perché verrebbero scritti nei file generati.

## Licenza

Il codice è distribuito con licenza **MIT**: puoi usarlo, copiarlo, modificarlo e ridistribuirlo, anche per scopi commerciali, a condizione di mantenere l'avviso di copyright e il testo della licenza. Il software è fornito *"così com'è"*, senza alcuna garanzia. Il testo completo (in inglese, l'unico giuridicamente valido) è nel file [LICENSE](LICENSE).

Chromium, Python e gli altri programmi richiamati dall'installer sono software di terze parti, distribuiti con le rispettive licenze.
