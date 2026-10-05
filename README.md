# Geardon 1.0.0 (WoW Forever)

Gegenstandsstufe (Itemlevel) für World of Warcraft: Forever (Client "Camelot", Interface 16001). In Forever speichert ein Gegenstand nur Gegenstandsstufe, Qualität und Werteverteilung, die Werte selbst berechnet das Spiel daraus. Die Gegenstandsstufe ist damit die Stärke eines Gegenstands.

## Installation
Ordner `Geardon` in den AddOns-Ordner des Forever-Clients kopieren (`...\Interface\AddOns\`). Im Spiel `/reload` oder neu einloggen.

## Funktionen
- **Charakterfenster:** Zahl an jedem angelegten Platz (ohne Hemd und Wappenrock). Der schwächste Platz steht in Orange. Dein Durchschnitt steht in der freien Ecke unten links, unter dem Handgelenksplatz, Blizzards Forever-Charakterfenster zeigt ihn nicht. Leere Plätze zählen wie im Spiel als 0, Geardon sagt dazu, wie viele leer sind.
- **Betrachten-Fenster:** Zahl je Platz und Durchschnitt unter dem Namen. Blizzards Forever-Fenster zeigt beides nicht. Liefert das Spiel einen eigenen Durchschnitt, wird dieser genommen, sonst rechnet Geardon (16 Plätze, Zweihandwaffe zählt doppelt bei leerer Schildhand).
- **Ausrüstungsauswahl:** Zahl auf allen Teilen, die du an einen Platz legen kannst (Alt über einem Platz im Charakterfenster). Den Verbesserungspfeil zeichnet Blizzard dort selbst.
- **Taschen, Bank, Beute, Questbelohnungen, Händler und Rückkauf:** Zahl auf Waffen und Rüstung, grüner Pfeil bei Verbesserungen. Verbesserung heißt: höher als das, was du an diesem Platz trägst, und jetzt tragbar (Klasse, Rüstungsart, Stufe). Ringe, Schmuckstücke und Einhandwaffen vergleichen mit dem schwächeren deiner beiden, ein leerer Platz zählt als 0. Eine Schildhand-Waffe oder ein Schild bekommt keinen Pfeil, solange du eine Zweihandwaffe trägst (sie würde sie ersetzen).
- **Tooltips:** "Gegenstandsstufe 18", nur wenn der Tooltip des Spiels keine eigene Zeile hat, dazu der Unterschied zu deinem Teil ("+3 gegenüber Kopf (15)"). Spieler-Tooltips zeigen die Gegenstandsstufe von Gruppenmitgliedern, die Geardon kennt.
- **Gruppe:** Gruppenmitglieder mit Geardon senden ihren Durchschnitt selbst (eine kurze Addon-Nachricht nur an die Gruppe). Alle anderen werden einzeln betrachtet: nur außerhalb des Kampfes, nie während Blizzards Betrachten-Fenster offen ist, nur sichtbare Spieler, 1,5 Sekunden Pause dazwischen, neu nach 10 Minuten oder neuer Ausrüstung. Mitglieder ohne Wert kommen zuerst dran. Ein kleines Fenster zeigt alle Mitglieder, die höchste Stufe zuerst, und den Gruppenschnitt (in Gruppen an, im Schlachtzug wahlweise). Der Tooltip einer Zeile nennt Quelle, Alter und den schwächsten Platz. Bekannte Werte überstehen ein `/reload` (15 Minuten).
- Englisch und Deutsch.

## Befehle
- `/gd` Optionen (auch unter Esc > Optionen > AddOns > Geardon)
- `/gd group` Gruppenfenster zeigen oder ausblenden
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
