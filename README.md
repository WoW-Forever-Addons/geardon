# Geardon 1.2.0 (WoW Forever)

Gegenstandsstufe (Itemlevel) für World of Warcraft: Forever (Client "Camelot", Interface 16001). In Forever speichert ein Gegenstand nur Gegenstandsstufe, Qualität und Werteverteilung, die Werte selbst berechnet das Spiel daraus. Die Gegenstandsstufe ist damit die Stärke eines Gegenstands.

## Installation
Ordner `Geardon` in den AddOns-Ordner des Forever-Clients kopieren (`...\Interface\AddOns\`). Im Spiel neu einloggen; nach einem Update mit neuen Dateien (wie 1.2.0) das Spiel ganz neu starten, `/reload` reicht dann nicht.

## Funktionen
- **Charakterfenster:** Zahl an jedem angelegten Platz (ohne Hemd und Wappenrock). Der schwächste Platz steht in Orange, Plätze weit hinter deiner Stufe in Rot. Der Tooltip des Durchschnitts nennt sie und die Dungeons für deine Stufe (aus Questdon, falls installiert), ein Klick öffnet den Ausrüstungscheck. Dein Durchschnitt steht in der freien Ecke unten links, unter dem Handgelenksplatz, Blizzards Forever-Charakterfenster zeigt ihn nicht. Leere Plätze zählen wie im Spiel als 0, Geardon sagt dazu, wie viele leer sind.
- **Betrachten-Fenster:** Zahl je Platz und Durchschnitt unter dem Namen. Blizzards Forever-Fenster zeigt beides nicht. Liefert das Spiel einen eigenen Durchschnitt, wird dieser genommen, sonst rechnet Geardon (16 Plätze, Zweihandwaffe zählt doppelt bei leerer Schildhand).
- **Ausrüstungsauswahl:** Zahl auf allen Teilen, die du an einen Platz legen kannst (Alt über einem Platz im Charakterfenster). Den Verbesserungspfeil zeichnet Blizzard dort selbst.
- **Taschen, Bank, Beute, Questbelohnungen, Händler und Rückkauf:** Zahl auf Waffen und Rüstung, grüner Pfeil bei Verbesserungen, Markierung für noch nicht gebundene Teile, die beim Anlegen binden. Auch in Baganator (Geardon in dessen Symbolecken und als Verbesserungs-Plugin wählen) und Bagnon. Verbesserung heißt: höher als das, was du an diesem Platz trägst, und jetzt tragbar (Klasse, Rüstungsart, Stufe), nur auf Waffenarten, die du nutzt, nicht auf Teilen ohne einen Hauptwert deiner Klasse und wahlweise nur auf deiner besten Rüstungsart. Forever berechnet die Werte aus Gegenstandsstufe und Qualität: Eine höhere Stufe in schlechterer Qualität bekommt einen gelben Pfeil (Werte vergleichen), ebenso ein Teil, das ein Teil eines aktiven Setbonus ersetzen würde. Ringe, Schmuckstücke und Einhandwaffen vergleichen mit dem schwächeren deiner beiden, ein leerer Platz zählt als 0. Eine Schildhand-Waffe oder ein Schild bekommt keinen Pfeil, solange du eine Zweihandwaffe trägst (sie würde sie ersetzen).
- **Tooltips:** "Gegenstandsstufe 18", nur wenn der Tooltip des Spiels keine eigene Zeile hat, dazu der Unterschied zu deinem Teil ("+3 gegenüber Kopf (15)") und die Werteverteilung ("Beweglichkeit 60 % · Ausdauer 40 %"), bei einem höheren Teil ohne Pfeil auch der Grund.
- **Jeder Spieler unter der Maus oder als Ziel** (Option, an): Seine Gegenstandsstufe erscheint im offenen Tooltip, sobald sie bekannt ist. Nur außerhalb des Kampfes, nie bei offenem Betrachten-Fenster, ein Spieler alle paar Sekunden; im Kampf der zuletzt bekannte Wert.
- **Chatzeile** bei neuem Durchschnitt, z. B. "Gegenstandsstufe 24,3 -> 25,1 (Kopf +6)". Nicht beim Einloggen, eine Zeile bei schnellem Wechsel.
- **Ausrüstungscheck** (`/gd check`): Plätze hinter deiner Stufe, Dungeons für deine Stufe und eine Liste zum Aufräumen der Taschen (schlechter als deins oder nicht nutzbar; Teile deiner Ausrüstungssets bleiben draußen). Nur eine Liste, nichts wird verkauft oder gelöscht.
- **Gruppe:** Gruppenmitglieder mit Geardon senden ihren Durchschnitt selbst (eine kurze Addon-Nachricht nur an die Gruppe). Alle anderen werden einzeln betrachtet: nur außerhalb des Kampfes, nie während Blizzards Betrachten-Fenster offen ist, nur sichtbare Spieler, 1,5 Sekunden Pause dazwischen, neu nach 10 Minuten oder neuer Ausrüstung. Mitglieder ohne Wert kommen zuerst dran. Ein kleines Fenster zeigt alle Mitglieder, die höchste Stufe zuerst, und den Gruppenschnitt; es öffnet sich nicht mehr von selbst, sondern mit `/gd group` oder dem Knopf in den Optionen. Der Tooltip einer Zeile nennt Quelle, Alter und den schwächsten Platz. Bekannte Werte überstehen ein `/reload` (15 Minuten).
- **Aussehen je Ort:** Lage und Größe der Zahlen getrennt für Charakterfenster, Taschen und Beute, Belohnungen und Händler; Farbe nach Abstand zu deinem Durchschnitt; Zahlen wahlweise erst ab "Selten".
- Englisch, Deutsch, Französisch, Spanisch (Spanien und Lateinamerika), brasilianisches Portugiesisch, Russisch, Koreanisch und traditionelles Chinesisch.

## Befehle
- `/gd` Optionen (auch unter Esc > Optionen > AddOns > Geardon)
- `/gd group` Gruppenfenster zeigen oder ausblenden
- `/gd check` Ausrüstungscheck
- `/gd scan` Gruppe neu betrachten
- `/gd diag` Diagnosefenster mit Bericht zum Kopieren, `/gd diag chat` im Chat
- `/gd help` alle Befehle

## Technik
- Nur eigene Rahmen: Die Zahlen sind eigene Frames als Kind der Gegenstandsknöpfe, ohne Maus. Klicks, Ziehen und Tooltips bleiben bei Blizzard. Keine Hooks auf Blizzard-Funktionen, kein Plündern, kein Ausrüsten aus Addon-Code.
- Sichtbarkeit: Ein unsichtbarer Hilfsrahmen als Kind des jeweiligen Blizzard-Fensters folgt dessen Ein- und Ausblenden. Geschlossene Fenster kosten nichts.
- Leistung: Unveränderte Knöpfe werden übersprungen (Gegenstand und Ausrüstung gleich), offene Taschen kosten im Sekundentakt nur einen kurzen Vergleich.
- Tooltips über `TooltipDataProcessor.AddTooltipPostCall` (wie Questdon).
- Spielfunktionen ohne gesperrte Rückgabewerte: `C_Item.GetDetailedItemLevelInfo`, `C_Item.GetCurrentItemLevel`, `C_PaperDollInfo.GetInspectItemLevel`, `C_PlayerInfo.CanUseItem`, `NotifyInspect`.

## Lizenz
MIT, siehe LICENSE.txt. Autor: DonCoohd.
