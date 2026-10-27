#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# ==============================================================================
# Installer Interattivo: Calendario Web (pagina HTML + CSV) in Chromium
# per Raspberry Pi / Ubuntu
# ==============================================================================
VERSIONE_INSTALLER="1.1"

# Novità mostrate quando questo installer aggiorna una versione precedente
# (aggiungi una riga per ogni modifica della versione corrente)
NOVITA=(
    "risolto l'errore CORS: il CSV viene scaricato da un piccolo server locale (server.py) e passato alla pagina"
    "se internet non è disponibile viene usata l'ultima copia salvata del CSV (entro un limite di ore)"
    "il calendario si apre sempre sul monitor primario (la scelta del monitor è stata rimossa)"
    "la console del browser (array del CSV, risposte, errori) e il server scrivono nel log completo e in error.log"
)

# Va eseguito con il proprio utente: se lanciato con sudo, si rilancia come utente normale
if [ "$(id -u)" -eq 0 ]; then
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        exec sudo -u "$SUDO_USER" env HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)" \
            bash "$(readlink -f "$0")" "$@"
    fi
    echo "Errore: esegui l'installer con il tuo utente, non come root." >&2
    exit 1
fi

# Percorsi principali
USER_HOME="$HOME"
TARGET_DIR="$USER_HOME/calendario-web"
LOG_DIR="$TARGET_DIR/logs"
SCRIPT_NAME="calendario-web.sh"
SCRIPT_PATH="$TARGET_DIR/$SCRIPT_NAME"
PAGE_NAME="calendario.html"
PAGE_PATH="$TARGET_DIR/$PAGE_NAME"
SERVER_PATH="$TARGET_DIR/server.py"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/calendario-web.desktop"
AUTOSTART_DUAL="$AUTOSTART_DIR/calendario-dual.desktop"   # installer a due monitor (se presente)

# Colori per Output Terminale (usati dopo la schermata iniziale)
CLR_RESET="\e[0m"
CLR_INFO="\e[1;32m"     # Verde Bold
CLR_WARN="\e[1;33m"     # Giallo Bold
CLR_ERR="\e[1;31m"      # Rosso Bold
CLR_HEAD="\e[1;35m"     # Magenta Bold

# Valori predefiniti (usati solo se non esiste una installazione precedente)
DEF_CSV="https://docs.google.com/spreadsheets/d/e/2PACX-1vSzaYrbe4Sr7dMUcYfX5VYFznywpGLtPO3eQqBaTt_pBbfZZdNMzqvTrIDlXhL-qF6akCwcTWLpBnfN/pub?gid=1504822993&single=true&output=csv"
DEF_REFRESH="300"       # secondi tra un aggiornamento dei dati e l'altro
DEF_DELAY="10"          # secondi di attesa dopo l'avvio del desktop

# Schermata iniziale: testo semplice, senza colori
mostra_header() {
    clear
    echo "============================================================"
    echo "        INSTALLER INTERATTIVO: CALENDARIO WEB (CSV)"
    echo "                       versione $VERSIONE_INSTALLER"
    echo "============================================================"
    echo
}

# ------------------------------------------------------------------------------
# Lettura dei valori dell'installazione precedente (da script e pagina installati)
# ------------------------------------------------------------------------------
leggi_var() {   # leggi_var NOME  (dallo script installato)
    [ -f "$SCRIPT_PATH" ] || return 0
    case "$1" in
        CSV_URL|VERSIONE_SCRIPT)
            sed -n "s/^$1=\"\([^\"]*\)\".*/\1/p" "$SCRIPT_PATH" | head -n1 ;;
        DELAY)
            sed -n 's/^DELAY=\([0-9][0-9]*\).*/\1/p' "$SCRIPT_PATH" | head -n1 ;;
    esac
}

leggi_pagina() {   # leggi_pagina url|refresh  (dalla pagina installata)
    [ -f "$PAGE_PATH" ] || return 0
    case "$1" in
        url)     sed -n 's/^ *var url = "\(.*\)";.*/\1/p' "$PAGE_PATH" | head -n1 ;;
        refresh) local ms; ms=$(sed -n 's/^ *var refresh_ms = \([0-9][0-9]*\);.*/\1/p' "$PAGE_PATH" | head -n1)
                 [ -n "$ms" ] && echo $((ms / 1000)) ;;
    esac
}

carica_precedenti() {
    VER_ATT=$(leggi_var VERSIONE_SCRIPT)
    P_CSV=$(leggi_var CSV_URL)
    if [ -z "$P_CSV" ]; then    # versione 1.0: il link era scritto nella pagina
        P_CSV=$(leggi_pagina url)
        case "$P_CSV" in http://*|https://*) ;; *) P_CSV="" ;; esac
    fi
    P_CSV="${P_CSV:-$DEF_CSV}"
    P_REFRESH=$(leggi_pagina refresh); P_REFRESH="${P_REFRESH:-$DEF_REFRESH}"
    P_DELAY=$(leggi_var DELAY);        P_DELAY="${P_DELAY:-$DEF_DELAY}"
    # Avvio automatico: se c'è già un'installazione si riparte dalla scelta fatta (file presente = sì)
    if [ -f "$SCRIPT_PATH" ] && [ ! -f "$AUTOSTART_FILE" ]; then P_AUTO="n"; else P_AUTO="s"; fi
}

# Confronto versioni: un suffisso come -rc.1 vale "prima" della versione finale
versione_minore() {   # versione_minore A B  -> successo se A < B
    local til='~' a b
    a="${1//-/$til}"; b="${2//-/$til}"
    [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" = "$a" ]
}

classifica_versione() {
    if [ ! -f "$SCRIPT_PATH" ]; then
        TIPO="nuova";         TIPO_TXT="nuova installazione, versione $VERSIONE_INSTALLER"
    elif [ -z "$VER_ATT" ]; then
        TIPO="aggiornamento"; TIPO_TXT="aggiornamento da una versione non numerata alla $VERSIONE_INSTALLER"
    elif [ "$VER_ATT" = "$VERSIONE_INSTALLER" ]; then
        TIPO="uguale";        TIPO_TXT="reinstallazione della stessa versione ($VERSIONE_INSTALLER)"
    elif versione_minore "$VER_ATT" "$VERSIONE_INSTALLER"; then
        TIPO="aggiornamento"; TIPO_TXT="aggiornamento da $VER_ATT a $VERSIONE_INSTALLER"
    else
        TIPO="declassamento"; TIPO_TXT="ritorno a una versione più vecchia: da $VER_ATT a $VERSIONE_INSTALLER"
    fi
}

# Schermata iniziale: testo semplice, senza colori
mostra_stato_versione() {
    case "$TIPO" in
        nuova)         echo "Stato: nessuna installazione trovata (questo installer contiene la versione $VERSIONE_INSTALLER)" ;;
        uguale)        echo "Stato: installata la versione $VER_ATT, uguale a quella di questo installer" ;;
        aggiornamento) echo "Stato: installata ${VER_ATT:-una versione non numerata} -> AGGIORNAMENTO DISPONIBILE alla $VERSIONE_INSTALLER" ;;
        declassamento) echo "Stato: installata la $VER_ATT, più recente di questo installer ($VERSIONE_INSTALLER)" ;;
    esac
    echo
}

mostra_banner_tipo() {
    case "$TIPO" in
        nuova)         echo -e "${CLR_INFO}>>> NUOVA INSTALLAZIONE (versione $VERSIONE_INSTALLER)${CLR_RESET}" ;;
        aggiornamento) echo -e "${CLR_INFO}>>> AGGIORNAMENTO: ${TIPO_TXT#aggiornamento }${CLR_RESET}" ;;
        uguale)        echo -e "${CLR_WARN}>>> REINSTALLAZIONE: la versione $VERSIONE_INSTALLER è già installata (script, pagina e server vengono riscritti)${CLR_RESET}" ;;
        declassamento) echo -e "${CLR_ERR}>>> ATTENZIONE: la versione installata ($VER_ATT) è PIÙ RECENTE di quella di questo installer ($VERSIONE_INSTALLER)${CLR_RESET}" ;;
    esac
    if [ "$TIPO" = "aggiornamento" ] && [ "${#NOVITA[@]}" -gt 0 ]; then
        echo "    Novità della versione $VERSIONE_INSTALLER:"
        local riga
        for riga in "${NOVITA[@]}"; do echo "      - $riga"; done
    fi
    echo
}

conferma_declassamento() {   # ritorna 1 se l'utente rinuncia
    [ "$TIPO" = "declassamento" ] || return 0
    read -rp "Installare comunque la versione più vecchia? (s/n) [default: n]: " RISP_DECL
    [[ "$RISP_DECL" =~ ^[Ss]$ ]] && return 0
    echo "Installazione annullata: non è stato modificato nulla."
    return 1
}

avvisa_installazione_dual() {   # evita di avere due avvii automatici di Chromium
    if [ -f "$AUTOSTART_DUAL" ]; then
        echo -e "${CLR_WARN}AVVISO: è presente anche l'avvio automatico del calendario a due monitor:${CLR_RESET}"
        echo -e "        $AUTOSTART_DUAL"
        echo -e "        Se non vuoi aprire entrambi all'accesso, rimuovilo con: rm \"$AUTOSTART_DUAL\""
        echo
    fi
}

# ------------------------------------------------------------------------------
funzione_purge() {
    echo -e "${CLR_WARN}--> [PURGE] RIMOZIONE DI TUTTI I FILE DELL'APPLICAZIONE...${CLR_RESET}"

    if [ -f "$AUTOSTART_FILE" ]; then
        rm -f "$AUTOSTART_FILE"
        echo -e "    - Rimosso file di avvio automatico ($AUTOSTART_FILE)."
    fi

    if [ -d "$TARGET_DIR" ]; then
        rm -rf "$TARGET_DIR"
        echo -e "    - Rimossa la cartella dell'applicazione ($TARGET_DIR): script, pagina, server, log e profilo del browser."
    fi

    echo -e "${CLR_INFO}--> Purge completato con successo.${CLR_RESET}"
    echo
}

valida_testo() {   # rifiuta i caratteri che romperebbero i file generati
    case "$1" in *\"*|*\\*|*\$*|*\`*|*\<*|*\>*|*' '*) return 1 ;; esac
    return 0
}

valida_url() {
    case "$1" in http://?*|https://?*) ;; *) return 1 ;; esac
    valida_testo "$1"
}

chiedi_config() {
    echo -e "${CLR_HEAD}------------------------------------------------------------${CLR_RESET}"
    echo -e "${CLR_HEAD}CONFIGURAZIONE (INVIO = conferma il valore tra parentesi)${CLR_RESET}"
    echo -e "${CLR_HEAD}------------------------------------------------------------${CLR_RESET}"
    read -rp "Link del file CSV da mostrare [default: $P_CSV]: " IN_CSV
    R_CSV="${IN_CSV:-$P_CSV}"

    read -rp "Aggiornamento dei dati ogni quanti secondi [default: $P_REFRESH]: " IN_REFRESH
    R_REFRESH="${IN_REFRESH:-$P_REFRESH}"

    read -rp "Secondi di attesa dopo l'avvio del desktop [default: $P_DELAY]: " IN_DELAY
    R_DELAY="${IN_DELAY:-$P_DELAY}"

    # Controllo dei valori: se non validi si usa il valore precedente
    valida_url "$R_CSV" || { echo -e "${CLR_WARN}Link CSV non valido (deve iniziare con http:// o https://, senza spazi né \" \\ \$ \` < >): uso '$P_CSV'${CLR_RESET}"; R_CSV="$P_CSV"; }
    case "$R_REFRESH" in ''|*[!0-9]*) echo -e "${CLR_WARN}Intervallo non valido ('$R_REFRESH'): uso $P_REFRESH${CLR_RESET}"; R_REFRESH="$P_REFRESH" ;; esac
    if [ "$R_REFRESH" -lt 10 ] 2>/dev/null; then echo -e "${CLR_WARN}Intervallo troppo breve (minimo 10 s): uso $P_REFRESH${CLR_RESET}"; R_REFRESH="$P_REFRESH"; fi
    case "$R_DELAY" in ''|*[!0-9]*) echo -e "${CLR_WARN}Attesa non valida ('$R_DELAY'): uso $P_DELAY${CLR_RESET}"; R_DELAY="$P_DELAY" ;; esac
    echo
}

# ------------------------------------------------------------------------------
# Pagina HTML: stessa pagina e stessa logica di visualizzazione dell'originale.
# Differenze: legge i dati da /dati.csv (server locale), intervallo di aggiornamento
# dalla configurazione e output di debug nella console.
# ------------------------------------------------------------------------------
genera_pagina() {
    echo -e "${CLR_INFO}--> Generazione della pagina ($PAGE_NAME)...${CLR_RESET}"
    mkdir -p "$TARGET_DIR"
    local riga HTML_TEMPLATE
    IFS= read -r -d '' HTML_TEMPLATE << 'FINE_HTML'
<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8">
        <title>Calendario</title>
    </head>
    <style>
        * {
            font-family: Arial;
            box-sizing: border-box;
        }
        #table_div{
            display: inline;
            position: absolute;
            top: 0;
            left: 0;
            padding: 0;
            margin: 0;

        }
        #msg{
            z-index: 5;
            transform: translate(-50%, -50%);
            position: fixed;
            top: 40%;
            left: 50%;
            font-size: 64px;
            color: black;
            text-align: center;
            font-weight: bold;
            display: block;
        }
        #table{
            position: relative;
            top: 0px;
            left: 0px;
            width: 100vw;
            height: 100vh;
            opacity: 0;
            margin: 0 !important;
            padding: 0 !important;
            font-size: 16px;
        }
        table, th, td{
            border: none;
            border-left: 1px solid #333;
            border-right: 1px solid #333;
            border-top: 1px dotted #cdcdcd;
            border-collapse: collapse !important;
            text-align: center;
            text-overflow: ellipsis;
            background-color: #fff;
        }
        th.date_head{
            height: calc(4vh - 1px) !important;
            /* min-height: 40px !important;
            max-height: 80px !important; */
            text-transform: uppercase;
        }
        p{
            position: relative;
            width: auto;
            height: auto;
            margin: 0;
            padding: 0;
        }
        p.date_head {
            font-size: 23px;
            line-height: 100%;
        }
        .col_0{
            width: 100px !important;
            font-weight: bold;
            text-align: center;
            font-size: 16px;
        }
        tr{
            height: calc(96% / 30);
            background-color: #fff;
        }
        tr:nth-child(2n) > td{
            background-color: #eee;
        }
        .row_1, .row_17{
            font-size: 20px;
            font-weight: bold;
            border-top: 3px solid #333;
            border-bottom: 2px dotted #333;
            background-color: #aaa !important;
        }
        .row_2, .row_18{
            font-size: 18px;
            font-style: italic;
            border-bottom: 3px double #333;
        }
    </style>

    <body>
        <div id="table_div">
            <p id="msg">Caricamento...</p>
            <table id="table" class="table">
                
            </table>
        </div>

    </body>


    <script>
        // ---- DEBUG: i messaggi "[calendario]" compaiono nella console del browser (F12)
        // e vengono copiati nel log dallo script di avvio.
        // 0 = nessun messaggio | 1 = riepilogo + array del CSV | 2 = anche il dettaglio di ogni cella evidenziata
        var DEBUG = 1;
        var dbg = (...args) => { if (DEBUG > 0) console.log("[calendario]", ...args); };

        window.addEventListener("error", (e) => {
            console.error("[calendario] errore JavaScript:", e.message, "(riga " + e.lineno + ")");
        });
        window.addEventListener("unhandledrejection", (e) => {
            console.error("[calendario] operazione fallita:", (e.reason && e.reason.message) ? e.reason.message : e.reason);
        });

        var table = document.getElementById("table");
        var url = "/dati.csv";   // lo scarica il server locale (server.py) dal link CSV configurato
        var refresh_ms = @@REFRESH_MS@@;
        var words = [
            ["assente", "assenza", "ass"],
            ["malattia","malato","malata"],
            ["stand-by", "standby", "stand by", "stanby"],
            ["emergenza", "eme", "118"],
            ["notte"],
            ["trasferimenti", "trasf", "tras"]
        ];

        var cell_color = [
            "rgb(170, 170, 170)",
            "rgb(170, 170, 170)",
            "rgb(255, 145, 0)",
            "rgb(251, 255, 0)",
            "rgb(0, 255, 166)",
            "rgb(56, 238, 6)"
        ];

        dbg("pagina avviata:", location.href);
        dbg("dati da:", url, "| aggiornamento ogni", refresh_ms / 1000, "s | schermo:", window.innerWidth + "x" + window.innerHeight);
        dbg("browser:", navigator.userAgent);
        
        
        let print_calendar = (arr) => {
            var table = document.getElementById("table");
            table.style.opacity = "100";

            var row_data = "";
            for (let row = 0; row < arr.length; row++) {
                row_data += "<tr class='row_" + row + " tr_table'>";

                if(row == 0){
                    row_data += "<th class='date_head' colspan='" + arr[0].length + "'><p class='date_head'>" + arr[0][1] + "</p></th>";

                }else{
                    for (let col = 0; col < arr[row].length; col++) {
                        row_data += "<td class='col_" + col + "' id='td_" + col + "_" + row + "' style='width: calc((100vw - 100px) / " + parseInt(arr[row].length - 1) + ")'><p id='p_" + col + "_" + row + "'>" + arr[row][col] + "</p></td>";
                    }
                }

                row_data += "</tr>";


            }
            table.innerHTML = row_data;
            console.log(arr);

            var parole_trovate = 0, celle_evidenziate = 0;
            
            for (let row = 3; row < arr.length; row++) {
                for (let col = 1; col < arr[row].length; col++) {
                    if(row < 16 || row > 18){
                        
                        var cell_cont = document.getElementById("p_" + col + "_" + row).innerHTML;
                        cell_cont.replace(" ", "");
                        cell_cont.replace("\r", "");
                        
                        for (let index = 0; index < words.length; index++) {
                            if(words[index].includes(cell_cont.toLowerCase())){
                                parole_trovate++;
                                if(DEBUG > 1) dbg("parola chiave '" + cell_cont + "' alla riga", row, "colonna", col, "-> colore", cell_color[index]);
                                if(row < 16){
                                    for (let i = 3; i < 16; i++) {
                                        document.getElementById("td_" + col + "_" + i).style.backgroundColor = cell_color[index];
                                    }
                                }else{
                                    for (let i = 19; i < 30; i++) {
                                        document.getElementById("td_" + col + "_" + i).style.backgroundColor = cell_color[index];
                                    }
                                }
                            }
                        }

                        
                        if(cell_cont == cell_cont.toUpperCase() && isNaN(cell_cont[0])){
                            if(!(console.log(cell_color.includes(document.getElementById("td_" + col + "_" + row).style.backgroundColor)))){
                                celle_evidenziate++;
                                if(DEBUG > 1) dbg("cella in maiuscolo '" + cell_cont + "' alla riga", row, "colonna", col, "evidenziata");
                                document.getElementById("p_" + col + "_" + row).style.backgroundColor = "rgba(255,161,54,0.6)";
                                document.getElementById("p_" + col + "_" + row).style.fontWeight = "bold";
                                document.getElementById("p_" + col + "_" + row).style.fontStyle = "italic";
                        
                            }
                        }

                    }
                }
                    
            }

            dbg("tabella disegnata: righe =", arr.length, "| celle con parola chiave =", parole_trovate, "| celle evidenziate (maiuscolo) =", celle_evidenziate);
        };

        
        async function getCSV() {
            const t0 = performance.now();
            dbg("download dei dati: GET", url);
            const response = await fetch(url, { cache: "no-store" });
            dbg("risposta: HTTP", response.status, response.statusText,
                "| tipo:", response.headers.get("content-type"),
                "| dati dal server:", response.headers.get("x-cache"),
                "| età della copia:", response.headers.get("x-cache-age"), "s");
            if (!response.ok) {
                throw new Error("Failed to fetch CSV (HTTP " + response.status + ")");
            }
            const csvData = await response.text();
            dbg("CSV ricevuto:", csvData.length, "caratteri in", Math.round(performance.now() - t0), "ms");

            var lines=csvData.split("\n");
            dbg("righe nel CSV:", lines.length, "| prime righe:", JSON.stringify(lines.slice(0, 3)));
            var result = [];
            for(let i = 0; i < lines.length; i++) {
                var line_arr = ["","","","","","","","","",""];
                var cells = lines[i].split(",");
                for (let j = 0; j < cells.length; j++) {
                    line_arr[j] = cells[j].replace("\r", "");
                }
                result.push(line_arr);
            }
            dbg("array ottenuto dal CSV:", result.length, "righe x", result[0].length, "colonne");
            console.log("[calendario] array CSV:", result);
            if (DEBUG > 0) console.log("[calendario] array CSV (JSON): " + JSON.stringify(result));
            document.getElementById("msg").style.display = "none";


            print_calendar(result);
            dbg("completato in", Math.round(performance.now() - t0), "ms");
        }




        getCSV();

//        setInterval(() => {
//            getCSV();
//        }, 10000);
	setTimeout(() => {
	    dbg("ricarico la pagina per aggiornare i dati");
	    location.reload();
	}, refresh_ms);


    </script>

</html>
FINE_HTML
    {
        while IFS= read -r riga; do
            case "$riga" in
                *@@REFRESH_MS@@*) printf '        var refresh_ms = %s;\n' "$((R_REFRESH * 1000))" ;;
                *)                printf '%s\n' "$riga" ;;
            esac
        done <<< "$HTML_TEMPLATE"
    } > "$PAGE_PATH"
    echo -e "${CLR_INFO}--> Pagina creata in $PAGE_PATH${CLR_RESET}"
}

# ------------------------------------------------------------------------------
# Server locale (Python, solo libreria standard): serve la pagina e fa da ponte
# verso il CSV remoto, perché il browser non può leggerlo direttamente (CORS)
# ------------------------------------------------------------------------------
genera_server() {
    echo -e "${CLR_INFO}--> Generazione del server locale (server.py)...${CLR_RESET}"
    mkdir -p "$TARGET_DIR"
    cat > "$SERVER_PATH" << 'FINE_SERVER'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Server locale del calendario web.

Serve la pagina calendario.html e fa da "ponte" verso il CSV remoto: il browser
non puo' leggere direttamente il CSV di Google (blocco CORS), quindi lo scarica
questo programma e lo passa alla pagina dallo stesso indirizzo (/dati.csv).
Se internet non e' disponibile usa l'ultima copia salvata (entro il limite indicato).
Ascolta solo su 127.0.0.1.
"""
import argparse
import os
import signal
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("--dir", required=True)
parser.add_argument("--port", type=int, required=True)
parser.add_argument("--csv-url", required=True)
parser.add_argument("--cache", required=True)
parser.add_argument("--log-full", required=True)
parser.add_argument("--log-err", required=True)
parser.add_argument("--timeout", type=int, default=20)
parser.add_argument("--max-stale", type=int, default=86400)
args = parser.parse_args()

lock = threading.Lock()


def log(livello, msg):
    """Scrive sul terminale e nei log (gli ERROR anche in error.log)."""
    riga = "[%s] [%s] [server] %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), livello, msg)
    with lock:
        try:
            sys.stdout.write(riga)
            sys.stdout.flush()
        except (OSError, ValueError):
            pass
        for percorso, ammesso in ((args.log_full, True), (args.log_err, livello == "ERROR")):
            if ammesso:
                try:
                    with open(percorso, "a", encoding="utf-8") as f:
                        f.write(riga)
                except OSError:
                    pass


def scarica_csv():
    richiesta = urllib.request.Request(
        args.csv_url,
        headers={"User-Agent": "Mozilla/5.0 (calendario-web)", "Accept": "text/csv,*/*"},
    )
    t0 = time.time()
    with urllib.request.urlopen(richiesta, timeout=args.timeout) as r:
        dati = r.read()
        stato = r.status
        finale = r.geturl()
    ms = int((time.time() - t0) * 1000)
    if not dati.strip():
        raise ValueError("risposta vuota")
    if dati.lstrip()[:15].lower().startswith((b"<!doctype html", b"<html")):
        raise ValueError("la risposta e' una pagina HTML e non un CSV (il foglio e' pubblicato sul web in formato CSV?)")
    return dati, stato, finale, ms


def salva_copia(dati):
    tmp = args.cache + ".tmp"
    try:
        with open(tmp, "wb") as f:
            f.write(dati)
        os.replace(tmp, args.cache)
    except OSError as e:
        log("WARN", "impossibile salvare la copia del CSV: %s" % e)


def leggi_copia():
    """Ritorna (dati, eta_in_secondi) oppure None."""
    try:
        eta = time.time() - os.path.getmtime(args.cache)
        with open(args.cache, "rb") as f:
            return f.read(), eta
    except OSError:
        return None


class Gestore(BaseHTTPRequestHandler):
    server_version = "calendario-web"

    def log_message(self, fmt, *a):   # il log lo gestiamo noi
        pass

    def invia(self, codice, corpo, tipo="text/plain; charset=utf-8", extra=None):
        try:
            self.send_response(codice)
            self.send_header("Content-Type", tipo)
            self.send_header("Content-Length", str(len(corpo)))
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(corpo)
        except (BrokenPipeError, ConnectionResetError):
            log("WARN", "connessione chiusa dal browser durante la risposta a %s" % self.path)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        percorso = self.path.split("?", 1)[0]
        if percorso in ("/", "/calendario.html"):
            self.pagina()
        elif percorso == "/dati.csv":
            self.csv()
        elif percorso == "/favicon.ico":
            self.invia(204, b"")
        else:
            log("WARN", "richiesta non valida: %s -> 404" % self.path)
            self.invia(404, b"non trovato")

    def pagina(self):
        try:
            with open(os.path.join(args.dir, "calendario.html"), "rb") as f:
                corpo = f.read()
        except OSError as e:
            log("ERROR", "pagina non leggibile: %s" % e)
            self.invia(500, b"pagina non trovata")
            return
        log("INFO", "GET /calendario.html -> 200 (%d byte)" % len(corpo))
        self.invia(200, corpo, "text/html; charset=utf-8")

    def csv(self):
        try:
            dati, stato, finale, ms = scarica_csv()
        except Exception as e:   # rete, DNS, HTTP, risposta non valida...
            log("ERROR", "download del CSV fallito: %s: %s" % (type(e).__name__, e))
            copia = leggi_copia()
            if copia and copia[1] <= args.max_stale:
                dati, eta = copia
                log("WARN", "uso la copia salvata del CSV (%d byte, di %d secondi fa)" % (len(dati), eta))
                self.invia(200, dati, "text/csv; charset=utf-8",
                           {"X-Cache": "stale", "X-Cache-Age": str(int(eta))})
            else:
                motivo = "nessuna copia salvata" if not copia else "la copia salvata e' troppo vecchia (%d s)" % copia[1]
                log("ERROR", "%s: rispondo 503" % motivo)
                self.invia(503, ("CSV non disponibile: %s" % e).encode("utf-8"))
            return
        salva_copia(dati)
        log("INFO", "CSV scaricato: HTTP %s, %d byte, %d righe, %d ms (%s)" % (
            stato, len(dati), dati.count(b"\n") + 1, ms, finale[:100]))
        self.invia(200, dati, "text/csv; charset=utf-8", {"X-Cache": "fresh", "X-Cache-Age": "0"})


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def ferma(signo, frame):
    log("INFO", "server fermato (segnale %d)" % signo)
    os._exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, ferma)
    server = Server(("127.0.0.1", args.port), Gestore)
    log("INFO", "server avviato su http://127.0.0.1:%d/ | CSV: %s" % (args.port, args.csv_url))
    log("INFO", "copia di riserva: %s (valida %d ore) | timeout download: %d s" % (
        args.cache, args.max_stale // 3600, args.timeout))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("INFO", "server fermato (Ctrl+C)")
FINE_SERVER
    chmod +x "$SERVER_PATH"
    echo -e "${CLR_INFO}--> Server creato in $SERVER_PATH${CLR_RESET}"
}

# ------------------------------------------------------------------------------
# Script di avvio: avvia il server locale, apre Chromium sul monitor primario
# e tiene tutto sotto controllo
# ------------------------------------------------------------------------------
genera_script() {
    echo -e "${CLR_INFO}--> Generazione dello script di avvio ($SCRIPT_NAME)...${CLR_RESET}"
    mkdir -p "$LOG_DIR"

    {
        # --- Parte 1: configurazione, con i valori scelti ora ---
        cat << EOF
#!/bin/bash
[ -z "\$BASH_VERSION" ] && exec bash "\$0" "\$@"

# ---- CONFIGURAZIONE (scritta da install-calendario-web.sh v$VERSIONE_INSTALLER) -----
VERSIONE_SCRIPT="$VERSIONE_INSTALLER"   # letta dall'installer per riconoscere gli aggiornamenti
CSV_URL="$R_CSV"    # link del CSV: lo scarica il server locale (server.py)
DELAY=$R_DELAY              # secondi di attesa prima di iniziare
TENTATIVI=5         # tentativi di rilevamento monitor
PAUSA=3             # secondi tra un tentativo e l'altro
BROWSER_FORZATO=""  # percorso opzionale browser
INTERVALLO_CONTROLLO=120    # secondi tra un controllo e l'altro (silenzioso)
TIMEOUT_CSV=20      # secondi massimi per scaricare il CSV
COPIA_MAX_ORE=24    # se internet manca, ore per cui si usa l'ultima copia salvata del CSV
MAX_LOG_KB=5120     # oltre questa dimensione i log vengono ruotati (copia .old)
# ------------------------------------------------------------------------
EOF
        # --- Parte 2: logica dello script (nessuna espansione di variabili) ---
        cat << 'FINE_SCRIPT'

# Se lanciato con sudo, Chromium non parte: si rilancia come utente reale.
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    UHOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    UID_U=$(id -u "$SUDO_USER")
    XA="${XAUTHORITY:-}"
    if [ -z "$XA" ]; then
        XA=$(ls /run/user/"$UID_U"/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
        [ -z "$XA" ] && XA="$UHOME/.Xauthority"
    fi
    echo "Script lanciato con sudo: lo rilancio come utente '$SUDO_USER'..."
    exec sudo -u "$SUDO_USER" env \
        HOME="$UHOME" \
        DISPLAY="${DISPLAY:-:0}" \
        XAUTHORITY="$XA" \
        XDG_RUNTIME_DIR="/run/user/$UID_U" \
        bash "$(readlink -f "$0")" "$@"
fi

# ---- PERCORSI E LOG -----------------------------------------------------
DIR_APP="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DIR_LOGS="$DIR_APP/logs"
LOG_FULL="$DIR_LOGS/calendario.log"     # log completo: avvio, monitoraggio, server, console del browser
LOG_ERR="$DIR_LOGS/error.log"           # solo errori
PAGINA="$DIR_APP/calendario.html"
SERVER_PY="$DIR_APP/server.py"
CACHE_CSV="$DIR_APP/dati-cache.csv"
PROFILO="$DIR_APP/profilo"              # cartella non nascosta: necessario per Chromium snap

mkdir -p "$DIR_LOGS"

# ---- COLORI OUTPUT TERMINALE --------------------------------------------
C_RST="\e[0m"
C_TM="\e[1;36m"   # Ciano (Ora)
C_INF="\e[1;32m"  # Verde (Info)
C_WRN="\e[1;33m"  # Giallo (Warning)
C_ERR="\e[1;31m"  # Rosso (Errore)

export DISPLAY="${DISPLAY:-:0}"

# Strip dei colori ANSI prima di scrivere nei file di log
pulisci_ansi() {
    echo -e "$1" | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g"
}

log() {
    local stamp="${C_TM}[$(date '+%Y-%m-%d %H:%M:%S')]${C_RST}"
    local msg="$stamp ${C_INF}[INFO]${C_RST} $*"
    echo -e "$msg"
    pulisci_ansi "$msg" >> "$LOG_FULL"
}

log_warn() {
    local stamp="${C_TM}[$(date '+%Y-%m-%d %H:%M:%S')]${C_RST}"
    local msg="$stamp ${C_WRN}[WARN]${C_RST} $*"
    echo -e "$msg"
    pulisci_ansi "$msg" >> "$LOG_FULL"
}

log_error() {
    local stamp="${C_TM}[$(date '+%Y-%m-%d %H:%M:%S')]${C_RST}"
    local msg="$stamp ${C_ERR}[ERROR]${C_RST} $*"
    echo -e "$msg" >&2
    pulisci_ansi "$msg" >> "$LOG_FULL"
    pulisci_ansi "$msg" >> "$LOG_ERR"
}

info() {
    local msg="           $*"
    echo -e "$msg"
    pulisci_ansi "$msg" >> "$LOG_FULL"
}

# Dettaglio di un errore: terminale + log completo + error.log
info_err() {
    printf '           %s\n' "$*" >&2
    printf '           %s\n' "$*" >> "$LOG_FULL"
    printf '           %s\n' "$*" >> "$LOG_ERR"
}

# Solo nel log completo, nessun output a terminale
log_file() {
    printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FULL"
}

# Ruota i log troppo grandi (copia in .old e svuota)
ruota_log() {
    local f
    for f in "$LOG_FULL" "$LOG_ERR"; do
        if [ -f "$f" ] && [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -gt $((MAX_LOG_KB * 1024)) ]; then
            cp -f "$f" "$f.old" && : > "$f"
        fi
    done
}

SESSIONE="${XDG_SESSION_TYPE:-}"
if [ -z "$SESSIONE" ]; then
    if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-wayland-0}" ]; then
        SESSIONE="wayland"
    else
        SESSIONE="x11"
    fi
fi
SISTEMA=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
MODELLO=""
[ -r /proc/device-tree/model ] && MODELLO=$(tr -d '\0' < /proc/device-tree/model)

attendi_chiusura() {
    echo
    read -rp "Premi INVIO per chiudere questo terminale..." _
}

PID=""          # browser
PID_SRV=""      # server locale
OUT=""          # output del browser (file temporaneo)
OUT_SRV=""      # errori del server (file temporaneo)
OUT_OFFSET=0    # quanto dell'output del browser è già stato letto
AVVISO_XDOTOOL=""
CHIUSURA_FATTA=0
MOTIVO_USCITA=""

conta_monitor_attivi() {
    xrandr --query 2>/dev/null | grep ' connected' | grep -cE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+'
}

# Console del browser: copia nei log (e sul terminale) i messaggi della pagina.
# Passano solo i messaggi "[calendario]" della pagina e gli errori/avvisi della console.
inoltra_console_browser() {
    [ -n "$OUT" ] && [ -f "$OUT" ] || return 0
    local size nuovi riga testo
    size=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
    [ "$size" -lt "$OUT_OFFSET" ] && OUT_OFFSET=0
    [ "$size" -eq "$OUT_OFFSET" ] && return 0
    nuovi=$(tail -c +"$((OUT_OFFSET + 1))" "$OUT" 2>/dev/null | head -c $((size - OUT_OFFSET)) | grep -a 'CONSOLE')
    OUT_OFFSET=$size
    [ -z "$nuovi" ] && return 0
    while IFS= read -r riga; do
        case "$riga" in
            *'[calendario]'*|*ERROR:CONSOLE*|*WARNING:CONSOLE*) ;;
            *) continue ;;
        esac
        testo="${riga#*CONSOLE}"
        testo="${testo#*\] }"
        case "$riga" in
            *ERROR:CONSOLE*)   log_error "[browser] ${testo:0:2000}" ;;
            *WARNING:CONSOLE*) log_warn "[browser] ${testo:0:600}" ;;
            *)                 printf '           [browser] %s\n' "${testo:0:300}"
                               log_file "[browser] ${testo:0:20000}" ;;
        esac
    done <<< "$nuovi"
}

# Il centro della finestra $1 è dentro il monitor primario? Imposta CX e CY.
centro_in_monitor() {
    local wid=$1 out wx wy ww wh
    out=$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null) || return 2
    wx=$(echo "$out" | sed -n 's/^X=//p');     wy=$(echo "$out" | sed -n 's/^Y=//p')
    ww=$(echo "$out" | sed -n 's/^WIDTH=//p'); wh=$(echo "$out" | sed -n 's/^HEIGHT=//p')
    [ -z "$wx" ] || [ -z "$ww" ] && return 2
    CX=$((wx + ww / 2)); CY=$((wy + wh / 2))
    if [ "$CX" -ge "$MON_X" ] && [ "$CX" -lt $((MON_X + MON_W)) ] &&
       [ "$CY" -ge "$MON_Y" ] && [ "$CY" -lt $((MON_Y + MON_H)) ]; then
        return 0
    fi
    return 1
}

finestre_chromium() {
    xdotool search --onlyvisible --class "chrom" 2>/dev/null | sort -u
}

# Verifica (ed eventualmente corregge) la posizione della finestra appena aperta.
# $1 = finestre Chromium presenti PRIMA dell'avvio: quella cercata è la più grande tra le nuove.
verifica_finestra() {
    local prima=$1 wid="" n id out w h area best=0
    if ! command -v xdotool >/dev/null; then
        if [ -z "$AVVISO_XDOTOOL" ]; then
            info "Verifica posizione saltata: installa xdotool e wmctrl"
            AVVISO_XDOTOOL=1
        fi
        return
    fi
    for ((n = 1; n <= 10; n++)); do
        best=0; wid=""
        for id in $(finestre_chromium); do
            grep -qx "$id" <<< "$prima" && continue
            out=$(xdotool getwindowgeometry --shell "$id" 2>/dev/null)
            w=$(echo "$out" | sed -n 's/^WIDTH=//p'); h=$(echo "$out" | sed -n 's/^HEIGHT=//p')
            [ -z "$w" ] && continue
            area=$((w * h))
            if [ "$area" -gt "$best" ]; then best=$area; wid=$id; fi
        done
        [ -n "$wid" ] && break
        sleep 1
    done
    if [ -z "$wid" ]; then
        info "Nessuna nuova finestra Chromium trovata: posizione non verificabile."
        return
    fi
    centro_in_monitor "$wid"
    case $? in
        0) log "Posizione OK: finestra sul monitor $MON_NOME (centro $CX,$CY)."; return ;;
        2) info "Impossibile leggere la geometria della finestra."; return ;;
    esac

    log_warn "La finestra NON è sul monitor $MON_NOME (centro $CX,$CY)."
    if ! command -v wmctrl >/dev/null; then
        info "Per correggere automaticamente installa wmctrl (sudo apt install wmctrl)."
        return
    fi
    info "Provo a spostarla in $MON_X,$MON_Y..."
    wmctrl -i -r "$wid" -b remove,fullscreen
    xdotool windowmove "$wid" "$MON_X" "$MON_Y"
    sleep 1
    wmctrl -i -r "$wid" -b add,fullscreen
    sleep 1
    if centro_in_monitor "$wid"; then
        log "Correzione riuscita: ora la finestra è sul monitor $MON_NOME (centro $CX,$CY)."
    else
        log_error "Correzione NON riuscita (centro $CX,$CY). Il window manager ignora lo spostamento."
    fi
}

istanza_viva() {
    { [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; } || pgrep -f -- "$PROFILO" >/dev/null 2>&1
}

server_vivo() {
    [ -n "$PID_SRV" ] && kill -0 "$PID_SRV" 2>/dev/null
}

# Chiude il browser e il server locale (prima con SIGTERM, poi con SIGKILL se serve)
chiudi_processi() {
    [ "$CHIUSURA_FATTA" -eq 1 ] && return
    CHIUSURA_FATTA=1
    inoltra_console_browser
    local n
    if [ -n "$PID" ]; then
        log "Chiusura della finestra del browser in corso..."
        kill -TERM -- "-$PID" 2>/dev/null
        pkill -TERM -f -- "$PROFILO" 2>/dev/null
        for ((n = 0; n < 10; n++)); do
            istanza_viva || break
            sleep 0.5
        done
        if istanza_viva; then
            info "Finestra ancora attiva: forzo la chiusura (SIGKILL)."
            kill -KILL -- "-$PID" 2>/dev/null
            pkill -KILL -f -- "$PROFILO" 2>/dev/null
        fi
        log "Finestra chiusa."
    fi
    if [ -n "$PID_SRV" ]; then
        kill -TERM -- "-$PID_SRV" 2>/dev/null
        for ((n = 0; n < 6; n++)); do
            server_vivo || break
            sleep 0.5
        done
        server_vivo && kill -KILL -- "-$PID_SRV" 2>/dev/null
        log "Server locale fermato."
    fi
}

errore_fatale() {
    echo
    log_error "$*"
    chiudi_processi
    attendi_chiusura
    exit 1
}

uscita_script() {
    local rc=$?
    if { [ -n "$PID" ] || [ -n "$PID_SRV" ]; } && [ "$CHIUSURA_FATTA" -eq 0 ]; then
        echo
        log_error "${MOTIVO_USCITA:-Script terminato inaspettatamente (codice $rc)}: chiudo finestra e server."
        chiudi_processi
    elif [ -n "$MOTIVO_USCITA" ]; then
        log_error "$MOTIVO_USCITA"
    fi
    rm -f "$OUT" "$OUT_SRV" 2>/dev/null
    log_file "===== Script terminato (codice $rc) ====="
}

trap 'MOTIVO_USCITA="Interruzione da tastiera (Ctrl+C)"; exit 130' INT
trap 'MOTIVO_USCITA="Segnale di terminazione (SIGTERM)"; exit 143' TERM
trap 'MOTIVO_USCITA="Terminale chiuso (SIGHUP)"; exit 129' HUP
trap uscita_script EXIT

# Avvia il server locale su una porta libera; ritorna 0 se risponde
avvia_server() {
    OUT_SRV=$(mktemp "${TMPDIR:-/tmp}/calendario-server.XXXXXX")
    PORTA=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])' 2>/dev/null)
    PORTA="${PORTA:-8765}"
    log "Avvio del server locale sulla porta $PORTA (scarica il CSV e lo passa alla pagina)..."
    setsid python3 -u "$SERVER_PY" \
        --dir "$DIR_APP" --port "$PORTA" --csv-url "$CSV_URL" \
        --cache "$CACHE_CSV" --log-full "$LOG_FULL" --log-err "$LOG_ERR" \
        --timeout "$TIMEOUT_CSV" --max-stale "$((COPIA_MAX_ORE * 3600))" 2>>"$OUT_SRV" &
    PID_SRV=$!
    local n
    for ((n = 0; n < 20; n++)); do
        server_vivo || return 1
        (exec 3<>"/dev/tcp/127.0.0.1/$PORTA") 2>/dev/null && return 0
        sleep 0.5
    done
    return 1
}

ruota_log
log_file "===== Avvio script v$VERSIONE_SCRIPT (PID $$, utente $(id -un)) ====="
log "=== Avvio calendario web (v$VERSIONE_SCRIPT) ==="
log "Sistema: ${SISTEMA:-sconosciuto}${MODELLO:+ ($MODELLO)} | utente: $(id -un) | sessione: $SESSIONE"
log "Link CSV: $CSV_URL"

if [ "$(id -u)" -eq 0 ]; then
    log_warn "ATTENZIONE: script eseguito come root: Chromium non partirà senza --no-sandbox."
fi

OZONE_ARGS=()
if [ "$SESSIONE" = "wayland" ]; then
    OZONE_ARGS=(--ozone-platform=x11)
    log "Sessione Wayland: Chromium sarà avviato in modalità X11 (XWayland)."
fi

for ((s = DELAY; s > 0; s--)); do
    printf "\r\e[1;36m[%s]\e[0m \e[1;33m[WAIT]\e[0m Avvio tra %2d secondi...   " "$(date +%H:%M:%S)" "$s"
    sleep 1
done
[ "$DELAY" -gt 0 ] && echo

for f in "$PAGINA" "$SERVER_PY"; do
    if [ ! -f "$f" ]; then
        log_error "File non trovato: $f (rilancia l'installer)."
        attendi_chiusura
        exit 1
    fi
done

if ! command -v python3 >/dev/null; then
    log_error "python3 non è installato (sudo apt install python3): serve per il server locale."
    attendi_chiusura
    exit 1
fi

if [ -n "$BROWSER_FORZATO" ]; then
    BROWSER=$(command -v "$BROWSER_FORZATO")
else
    BROWSER=$(command -v chromium-browser || command -v chromium || command -v google-chrome-stable || command -v google-chrome)
fi

if [ -z "$BROWSER" ]; then
    log_error "Nessun browser Chromium/Chrome trovato nel PATH."
    attendi_chiusura
    exit 1
fi

VERSIONE=$("$BROWSER" --version 2>/dev/null | head -1)
log "Browser: $BROWSER (${VERSIONE:-versione sconosciuta})"

if ! command -v xrandr >/dev/null; then
    log_error "Il comando xrandr non è installato."
    attendi_chiusura
    exit 1
fi

# ---- Rilevamento monitor (ordinati da sinistra a destra) ----------------
NOMI=(); GEOMS=(); PRIM=()
for ((t = 1; t <= TENTATIVI; t++)); do
    RAW=$(xrandr --query 2>&1)
    if [ $? -ne 0 ]; then
        log_error "xrandr ha restituito un errore: $RAW"
    fi

    ELENCO=$(echo "$RAW" | grep ' connected' | while read -r nome _; do
        riga=$(echo "$RAW" | grep "^$nome " | head -1)
        geom=$(echo "$riga" | grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | head -1)
        prim=0; case "$riga" in *" primary "*) prim=1 ;; esac
        [ -n "$geom" ] && echo "$(echo "$geom" | cut -d+ -f2) $prim $nome $geom"
    done | sort -n)

    NOMI=(); GEOMS=(); PRIM=()
    while read -r _x prim nome geom; do
        [ -z "$nome" ] && continue
        PRIM+=("$prim"); NOMI+=("$nome"); GEOMS+=("$geom")
    done <<< "$ELENCO"

    log_file "Rilevamento monitor, tentativo $t/$TENTATIVI: ${#NOMI[@]} attivi (${NOMI[*]})"
    [ "${#NOMI[@]}" -ge 1 ] && break
    if [ "$t" -lt "$TENTATIVI" ]; then
        log_warn "Nessun monitor attivo, riprovo tra $PAUSA secondi ($t/$TENTATIVI)..."
        sleep "$PAUSA"
    fi
done

if [ "${#NOMI[@]}" -lt 1 ]; then
    log_error "Nessun monitor attivo rilevato: impossibile aprire il calendario."
    attendi_chiusura
    exit 1
fi

# ---- Monitor primario (se xrandr non ne indica uno, si usa il primo da sinistra) ----
N_MON=${#NOMI[@]}
SEL=0; TROVATO=0
for idx in "${!PRIM[@]}"; do
    [ "${PRIM[$idx]}" = "1" ] && { SEL=$idx; TROVATO=1; break; }
done
[ "$TROVATO" -eq 0 ] && log_warn "xrandr non indica un monitor primario: uso il primo da sinistra (${NOMI[0]})."

RE='^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$'
if [[ "${GEOMS[$SEL]}" =~ $RE ]]; then
    MON_W=${BASH_REMATCH[1]}; MON_H=${BASH_REMATCH[2]}
    MON_X=${BASH_REMATCH[3]}; MON_Y=${BASH_REMATCH[4]}
    MON_NOME="${NOMI[$SEL]}"
else
    log_error "Geometria non interpretabile: '${GEOMS[$SEL]}'"
    attendi_chiusura
    exit 1
fi
log "Monitor attivi: $N_MON (${NOMI[*]}). Monitor primario: $MON_NOME ${MON_W}x${MON_H} ($MON_X,$MON_Y)"

# ---- Server locale ---------------------------------------------------------
if ! avvia_server; then
    log_error "Il server locale non è partito."
    info_err "Output del server:"
    tail -n 10 "$OUT_SRV" 2>/dev/null | while IFS= read -r riga; do info_err "$riga"; done
    errore_fatale "Avvio del server locale fallito."
fi
URL_PAGINA="http://127.0.0.1:$PORTA/calendario.html"
log "Server locale attivo: $URL_PAGINA"

# ---- Avvio della finestra ----------------------------------------------
# Output del browser in un file temporaneo: contiene anche la console della pagina
OUT=$(mktemp "${TMPDIR:-/tmp}/calendario-browser.XXXXXX")

PRIMA=""
command -v xdotool >/dev/null && PRIMA=$(finestre_chromium)

log "Apertura del calendario su $MON_NOME ($MON_X,$MON_Y)..."
setsid "$BROWSER" \
    --user-data-dir="$PROFILO" \
    --class="calendario-web" \
    "${OZONE_ARGS[@]}" \
    --window-position="$MON_X,$MON_Y" \
    --start-fullscreen \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --hide-crash-restore-bubble \
    --disable-features=Translate \
    --password-store=basic \
    --enable-logging=stderr \
    --new-window "$URL_PAGINA" >>"$OUT" 2>&1 &
PID=$!
log_file "Browser avviato (PID $PID, profilo $PROFILO)"

sleep 4

if kill -0 "$PID" 2>/dev/null; then
    verifica_finestra "$PRIMA"
    inoltra_console_browser
else
    log_error "Il browser è terminato subito."
    info_err "Ultime righe dell'output del browser:"
    tail -n 10 "$OUT" 2>/dev/null | while IFS= read -r riga; do info_err "$riga"; done
    errore_fatale "Avvio fallito."
fi

if [ "$INTERVALLO_CONTROLLO" -ge 60 ]; then
    ETICHETTA_INTERVALLO="$((INTERVALLO_CONTROLLO / 60)) min"
else
    ETICHETTA_INTERVALLO="${INTERVALLO_CONTROLLO} s"
fi
log "Calendario aperto. Controllo browser e server ogni $ETICHETTA_INTERVALLO in silenzio (dettagli in $LOG_FULL)."

# Ogni PASSO secondi si copia la console del browser nei log; ogni INTERVALLO_CONTROLLO si fa il controllo completo
PASSO=5
[ "$INTERVALLO_CONTROLLO" -lt "$PASSO" ] && PASSO=$INTERVALLO_CONTROLLO
CONTROLLO=0; TRASCORSO=0
while true; do
    sleep "$PASSO" & wait $!
    TRASCORSO=$((TRASCORSO + PASSO))
    inoltra_console_browser
    [ "$TRASCORSO" -lt "$INTERVALLO_CONTROLLO" ] && continue
    TRASCORSO=0
    CONTROLLO=$((CONTROLLO + 1))

    istanza_viva || errore_fatale "La finestra del calendario si è chiusa inaspettatamente."
    server_vivo  || errore_fatale "Il server locale si è fermato inaspettatamente."

    log_file "Controllo n. $CONTROLLO: finestra attiva (PID $PID), server attivo (PID $PID_SRV, porta $PORTA), monitor attivi: $(conta_monitor_attivi)"

    ruota_log
    # Tiene sotto controllo la dimensione dell'output temporaneo del browser
    [ -n "$(find "$OUT" -size +1M 2>/dev/null)" ] && : > "$OUT"
done
FINE_SCRIPT
    } > "$SCRIPT_PATH"

    chmod +x "$SCRIPT_PATH"
    echo -e "${CLR_INFO}--> Script di avvio creato in $SCRIPT_PATH${CLR_RESET}"
}

controlla_dipendenze() {
    echo -e "${CLR_HEAD}------------------------------------------------------------${CLR_RESET}"
    echo -e "${CLR_HEAD}CONTROLLO PROGRAMMI NECESSARI${CLR_RESET}"
    echo -e "${CLR_HEAD}------------------------------------------------------------${CLR_RESET}"
    local mancanti="" coppia
    for coppia in python3:python3 xrandr:x11-xserver-utils xdotool:xdotool wmctrl:wmctrl; do
        command -v "${coppia%%:*}" >/dev/null || mancanti="$mancanti ${coppia##*:}"
    done
    if [ -n "$mancanti" ]; then
        echo -e "${CLR_WARN}--> Mancano:$mancanti${CLR_RESET}"
        if command -v apt-get >/dev/null; then
            echo "    Installo con apt (potrebbe chiedere la password di sudo)..."
            if sudo apt-get install -y $mancanti >/dev/null 2>&1; then
                echo -e "${CLR_INFO}--> Installati:$mancanti${CLR_RESET}"
            else
                echo -e "${CLR_ERR}--> Installazione non riuscita. Fallo a mano: sudo apt install$mancanti${CLR_RESET}"
            fi
        else
            echo -e "${CLR_ERR}--> Installa a mano:$mancanti${CLR_RESET}"
        fi
    else
        echo -e "${CLR_INFO}--> Programmi necessari già presenti (python3, xrandr, xdotool, wmctrl).${CLR_RESET}"
    fi

    local browser
    browser=$(command -v chromium-browser || command -v chromium || command -v google-chrome-stable || command -v google-chrome)
    if [ -n "$browser" ]; then
        echo -e "${CLR_INFO}--> Browser trovato: $browser${CLR_RESET}"
    else
        echo -e "${CLR_ERR}--> Nessun browser Chromium/Chrome trovato. Raspberry Pi OS: sudo apt install chromium-browser | Ubuntu: sudo snap install chromium${CLR_RESET}"
    fi
    echo
}

comando_terminale() {   # sintassi diversa per ogni terminale
    if   command -v gnome-terminal    >/dev/null; then echo "gnome-terminal --title=\"Calendario\" --"
    elif command -v lxterminal        >/dev/null; then echo "lxterminal --title=\"Calendario\" -e"
    elif command -v xfce4-terminal    >/dev/null; then echo "xfce4-terminal --title=\"Calendario\" -x"
    elif command -v konsole           >/dev/null; then echo "konsole -e"
    else echo "x-terminal-emulator -e"
    fi
}

gestisci_autostart() {
    echo -e "${CLR_HEAD}------------------------------------------------------------${CLR_RESET}"
    echo -e "${CLR_HEAD}CONFIGURAZIONE AVVIO AUTOMATICO (AUTOSTART)${CLR_RESET}"
    echo -e "${CLR_HEAD}------------------------------------------------------------${CLR_RESET}"
    read -rp "Vuoi eseguire l'applicazione automaticamente ad ogni avvio del sistema? (s/n) [default: $P_AUTO]: " RISP_AUTO
    RISP_AUTO="${RISP_AUTO:-$P_AUTO}"

    if [[ "$RISP_AUTO" =~ ^[Ss]$ ]]; then
        mkdir -p "$AUTOSTART_DIR"
        cat << EOF > "$AUTOSTART_FILE"
[Desktop Entry]
Type=Application
Name=Calendario Web
Comment=Avvio automatico calendario (pagina HTML da CSV)
Exec=$(comando_terminale) "$SCRIPT_PATH"
Icon=utilities-terminal
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
        echo -e "${CLR_INFO}--> Avvio automatico configurato con successo!${CLR_RESET}"
        echo -e "    File autostart creato in: $AUTOSTART_FILE"
    else
        if [ -f "$AUTOSTART_FILE" ]; then
            rm -f "$AUTOSTART_FILE"
            echo -e "${CLR_WARN}--> Avvio automatico disabilitato/rimosso.${CLR_RESET}"
        else
            echo -e "--> Avvio automatico non configurato."
        fi
    fi
    echo
}

scrivi_nota_log() {   # lascia traccia dell'operazione nel log completo
    mkdir -p "$LOG_DIR"
    printf '[%s] [INFO] Installer v%s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$VERSIONE_INSTALLER" "$TIPO_TXT" >> "$LOG_DIR/calendario.log"
}

riepilogo_finale() {
    echo -e "${CLR_INFO}=== $1 ===${CLR_RESET}"
    echo "    Tipo di operazione: $TIPO_TXT"
    echo "    Script di avvio   : $SCRIPT_PATH"
    echo "    Pagina e server   : $PAGE_PATH, $SERVER_PATH"
    echo "    Log completo      : $LOG_DIR/calendario.log  (include server e console del browser)"
    echo "    Solo errori       : $LOG_DIR/error.log"
    echo "    Console del browser: si apre con F12 (messaggi che iniziano con [calendario])"
    echo "    Per cambiare link CSV o intervallo rilancia l'installer (opzione 2):"
    echo "    i valori di adesso saranno i predefiniti."
}

# ==============================================================================
# AVVIO
# ==============================================================================
carica_precedenti
classifica_versione

if [ "$1" = "--versione" ]; then
    if [ -f "$SCRIPT_PATH" ]; then
        echo "Versione installata        : ${VER_ATT:-non numerata}"
    else
        echo "Versione installata        : nessuna (non ancora installato)"
    fi
    echo "Versione in questo installer: $VERSIONE_INSTALLER"
    exit 0
fi

# ==============================================================================
# MENU PRINCIPALE (testo semplice, senza colori)
# ==============================================================================
mostra_header
mostra_stato_versione
echo "Scegli un'opzione per procedere:"
echo " 1) Installa"
echo " 2) Reinstalla / Aggiorna (aggiorna i file mantenendo i log)"
echo " 3) Reinstalla da zero (Purge completo + Nuova installazione)"
echo " 4) Disinstalla (Purge completo di tutti i file dell'applicazione)"
echo " 5) Esci"
echo "------------------------------------------------------------"
read -rp "Inserisci il numero dell'opzione scelta [1-5]: " SCELTA

case "$SCELTA" in
    1)
        mostra_header
        echo -e "${CLR_INFO}--> AVVIO INSTALLAZIONE...${CLR_RESET}"
        if [ -d "$TARGET_DIR" ]; then
            echo -e "${CLR_WARN}AVVISO: La cartella 'calendario-web' esiste già in $TARGET_DIR.${CLR_RESET}"
            echo -e "Se desideri aggiornarla scegli 'Reinstalla / Aggiorna' o 'Reinstalla da zero'."
            exit 1
        fi
        mostra_banner_tipo
        avvisa_installazione_dual
        chiedi_config
        genera_pagina
        genera_server
        genera_script
        gestisci_autostart
        controlla_dipendenze
        scrivi_nota_log
        riepilogo_finale "INSTALLAZIONE COMPLETATA CON SUCCESSO"
        ;;

    2)
        mostra_header
        echo -e "${CLR_INFO}--> AVVIO REINSTALLAZIONE / AGGIORNAMENTO...${CLR_RESET}"
        mostra_banner_tipo
        conferma_declassamento || exit 0
        avvisa_installazione_dual
        chiedi_config
        genera_pagina
        genera_server
        genera_script
        gestisci_autostart
        controlla_dipendenze
        scrivi_nota_log
        riepilogo_finale "REINSTALLAZIONE / AGGIORNAMENTO COMPLETATO"
        ;;

    3)
        mostra_header
        echo -e "${CLR_WARN}--> AVVIO REINSTALLAZIONE DA ZERO (PURGE + INSTALL)...${CLR_RESET}"
        mostra_banner_tipo
        conferma_declassamento || exit 0
        [ "$TIPO" != "nuova" ] && TIPO_TXT="reinstallazione da zero ($TIPO_TXT)"
        avvisa_installazione_dual
        # I valori precedenti sono già stati letti: restano come predefiniti anche dopo il purge
        funzione_purge
        chiedi_config
        genera_pagina
        genera_server
        genera_script
        gestisci_autostart
        controlla_dipendenze
        scrivi_nota_log
        riepilogo_finale "REINSTALLAZIONE DA ZERO COMPLETATA"
        ;;

    4)
        mostra_header
        echo -e "${CLR_ERR}--> AVVIO DISINSTALLAZIONE COMPLETA...${CLR_RESET}"
        read -rp "Sei sicuro di voler rimuovere tutti i file dell'applicazione? (s/n): " CONFERMA
        if [[ "$CONFERMA" =~ ^[Ss]$ ]]; then
            funzione_purge
            echo -e "${CLR_INFO}=== DISINSTALLAZIONE COMPLETATA ===${CLR_RESET}"
        else
            echo "Operazione annullata."
        fi
        ;;

    5)
        echo "Uscita."
        exit 0
        ;;

    *)
        echo -e "${CLR_ERR}Opzione non valida. Uscita.${CLR_RESET}"
        exit 1
        ;;
esac
