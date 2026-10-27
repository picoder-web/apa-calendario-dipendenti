# Calendario a schermo intero con Chromium (Raspberry Pi / Ubuntu)

![Licenza: MIT](https://img.shields.io/badge/Licenza-MIT-yellow.svg)
![Piattaforma](https://img.shields.io/badge/Piattaforma-Raspberry%20Pi%20OS%20%7C%20Ubuntu-blue)
![Shell](https://img.shields.io/badge/Shell-bash-green)

Installer interattivi che trasformano un Raspberry Pi o un PC Ubuntu in un **display a schermo intero** per il calendario: Chromium viene aperto in automatico all'avvio del desktop, controllato in continuazione e chiuso in modo pulito in caso di errore.

## Indice

- [Panoramica](#panoramica)
- [Requisiti](#requisiti)
- [Installazione rapida](#installazione-rapida)
- [Calendario Web (CSV → pagina HTML)](#calendario-web-csv--pagina-html)
  - [Come funziona](#come-funziona)
  - [Formato del CSV](#formato-del-csv)
  - [File installati](#file-installati)
  - [Configurazione](#configurazione)
  - [Log e debug](#log-e-debug)
- [Calendario a due monitor](#calendario-a-due-monitor)
- [Aggiornamenti e versioni](#aggiornamenti-e-versioni)
- [Disinstallazione](#disinstallazione)
- [Risoluzione dei problemi](#risoluzione-dei-problemi)
- [Note su privacy e sicurezza](#note-su-privacy-e-sicurezza)
- [Licenza](#licenza)

## Panoramica

| | **Calendario Web** |
|---|---|
| Installer | `install.sh` |
| Cosa fa | Mostra una tabella calendario costruita da un file **CSV** (ad esempio un foglio Google pubblicato sul web) in una finestra a schermo intero sul **monitor primario** |
| Versione | 1.1 |
| Cartella di installazione | `~/calendario-web` |

## Requisiti

- **Sistema:** Raspberry Pi OS o Ubuntu (e derivate) con desktop grafico. È consigliata una sessione **X11**; con **Wayland** Chromium viene avviato in modalità X11 (XWayland) per poter posizionare le finestre.
- **Browser:** Chromium o Google Chrome.
  - Raspberry Pi OS: `sudo apt install chromium-browser` (oppure `chromium`)
  - Ubuntu: `sudo snap install chromium`
- **Programmi di supporto**, installati automaticamente dall'installer con `apt` se mancano (può chiedere la password di `sudo`):
  `python3` (solo Calendario Web), `x11-xserver-utils` (`xrandr`), `xdotool`, `wmctrl`.
- **Connessione a internet** (per scaricare il CSV nel Calendario Web).

## Installazione rapida

```bash
git clone https://github.com/picoder-web/apa-calendario.git
cd apa-calendario
chmod +x install-calendario-web.sh      # oppure install.sh per il calendario a due monitor
./install-calendario-web.sh
```

> **Non lanciare l'installer con `sudo`.** Va eseguito con il tuo utente normale: i file vengono installati nella tua home e Chromium non parte se eseguito come root. Se per sbaglio usi `sudo`, l'installer si rilancia da solo con l'utente che ha usato `sudo`.

All'avvio compare un menu:

| Opzione | Cosa fa |
|---|---|
| **1) Installa** | Nuova installazione |
| **2) Reinstalla / Aggiorna** | Riscrive i file mantenendo i log; usata anche per cambiare link o impostazioni |
| **3) Reinstalla da zero** | Rimuove tutto (compreso il profilo del browser) e reinstalla |
| **4) Disinstalla** | Rimuove tutti i file dell'applicazione |
| **5) Esci** | Non modifica nulla |

Premendo INVIO a ogni domanda si confermano i valori tra parentesi quadre (quelli della volta precedente).

## Calendario Web (CSV → pagina HTML)

### Domande dell'installer

1. **Link del file CSV** da mostrare (deve iniziare con `http://` o `https://`).
2. **Ogni quanti secondi aggiornare i dati** (minimo 10, predefinito 300).
3. **Secondi di attesa dopo l'avvio del desktop** (predefinito 10).
4. **Avvio automatico** all'accesso al desktop (s/n).

### Come funziona

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

### Formato del CSV

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

### File installati

```text
~/calendario-web/
├── calendario-web.sh      # avvio, controllo e chiusura (con la configurazione in cima)
├── calendario.html        # la pagina che disegna la tabella
├── server.py              # server locale: pagina + CSV
├── dati-cache.csv         # ultima copia del CSV scaricato (creata a runtime)
├── profilo/               # profilo di Chromium (cartella non nascosta: serve per lo snap)
└── logs/
    ├── calendario.log     # log completo
    └── error.log          # solo errori
~/.config/autostart/calendario-web.desktop   # avvio automatico (se scelto)
```

### Configurazione

Link CSV, intervallo di aggiornamento, attesa e avvio automatico si cambiano **rilanciando l'installer** (opzione 2). Le altre impostazioni sono variabili in cima a `calendario-web.sh`:

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

> Le modifiche manuali a `calendario-web.sh` e a `calendario.html` vengono **sovrascritte** da una reinstallazione: vengono mantenuti solo i valori che l'installer richiede.

Il monitor usato è sempre il **monitor primario** indicato da `xrandr`. Se nessun monitor è primario viene usato il primo da sinistra e il fatto viene registrato nel log. Per cambiare il monitor primario: `xrandr --output NOME --primary`.

### Log e debug

- **`calendario.log`** (completo) contiene l'avvio, il rilevamento dei monitor, i messaggi del server (ogni download con esito, byte, righe e tempi), i messaggi della console del browser, un controllo periodico ogni 2 minuti (silenzioso a terminale) e le chiusure.
- **`error.log`** contiene solo gli errori: download falliti, errori della console del browser (compreso un eventuale blocco CORS), finestra o server chiusi inaspettatamente, interruzioni.
- Ogni riga ha il formato `[AAAA-MM-GG hh:mm:ss] [LIVELLO] messaggio`.

La pagina scrive nella **console del browser** (si apre con `F12`) messaggi che iniziano con `[calendario]`: indirizzo della pagina, richiesta e risposta (stato HTTP, dati nuovi o copia salvata), numero di righe del CSV, **l'array ottenuto dal CSV** (come oggetto espandibile e in JSON) e il riepilogo del disegno (righe, parole chiave trovate, celle evidenziate). Lo script di avvio copia questi messaggi, insieme agli errori della console, sul terminale e nei log.

Il livello di dettaglio si imposta con la variabile `DEBUG` in `calendario.html`: `0` = nessun messaggio, `1` = riepilogo e array del CSV (predefinito), `2` = anche ogni cella evidenziata.

## Calendario a due monitor

Installer: `install.sh` (cartella `~/calendario`).

Apre due finestre di Chromium a schermo intero, una per monitor, ciascuna con un link: il **primo link va sul monitor di sinistra** e il **secondo su quello di destra** (i monitor vengono ordinati per posizione, non per nome).

- Parte **solo se i monitor attivi sono esattamente 2**. Altrimenti non apre nulla e stampa il messaggio scelto all'installazione.
- Controlla che i monitor siano affiancati in orizzontale (segnala mirroring o monitor uno sopra l'altro) e che ogni finestra sia sullo schermo corretto.
- Ogni 2 minuti verifica che le due finestre siano aperte e che i monitor siano ancora 2; se no, chiude entrambe le finestre.

Domande dell'installer: link sinistra, link destra, messaggio se i monitor non sono 2, attesa dopo l'avvio del desktop, avvio automatico.

```text
~/calendario/
├── calendario.sh
└── logs/
    ├── calendario.log     # log completo
    └── error.log          # solo errori
~/chrome-dual-profili/     # profili di Chromium (uno per monitor)
```

## Aggiornamenti e versioni

Ogni installer contiene un numero di versione e lo confronta con quello già installato, mostrando:

- `NUOVA INSTALLAZIONE`;
- `AGGIORNAMENTO: da X a Y` (con l'elenco delle novità);
- `REINSTALLAZIONE` (stessa versione);
- un avviso se la versione installata è **più recente** di quella dell'installer, con richiesta di conferma.

Un suffisso come `-rc.1` conta come precedente alla versione finale (`2.2-rc.1` < `2.2`). Per vedere le versioni senza modificare nulla:

```bash
./install-calendario-web.sh --versione
```

Per aggiornare: scarica la nuova versione del repository, rilancia l'installer e scegli l'opzione **2**. Le versioni sono pubblicate nella sezione **Releases** del repository; la release segnata come *Latest* è l'ultima stabile e il ramo `main` corrisponde a quella.

## Disinstallazione

Rilancia l'installer e scegli l'opzione **4** (rimuove la cartella dell'applicazione, il profilo del browser e l'avvio automatico). Per togliere solo l'avvio automatico, elimina il file in `~/.config/autostart/` (`calendario-web.desktop` oppure `calendario-dual.desktop`).

## Risoluzione dei problemi

| Problema | Cosa fare |
|---|---|
| La pagina resta su "Caricamento..." | Guarda `logs/error.log`: di solito il foglio non è pubblicato come CSV, il link è sbagliato o manca la connessione. Con internet assente il server usa l'ultima copia salvata, se esiste |
| Errore *"blocked by CORS policy"* | Succede se la pagina legge direttamente il CSV di Google. Con l'installer attuale non dovrebbe comparire perché il CSV passa dal server locale; controlla di aver aggiornato all'ultima versione |
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
- I messaggi, i link e le impostazioni inseriti nell'installer non possono contenere i caratteri `"` `\` `$` `` ` `` (e, per il link CSV, `<`, `>` e spazi), perché verrebbero scritti nei file generati.

## Licenza

Il codice è distribuito con licenza **MIT**: puoi usarlo, copiarlo, modificarlo e ridistribuirlo, anche per scopi commerciali, a condizione di mantenere l'avviso di copyright e il testo della licenza. Il software è fornito *"così com'è"*, senza alcuna garanzia. Il testo completo (in inglese, l'unico giuridicamente valido) è nel file [LICENSE](LICENSE).

Chromium, Python e gli altri programmi richiamati dagli installer sono software di terze parti, distribuiti con le rispettive licenze.
