#!/bin/bash

## Variables

# Le script
currentDir=$(dirname $0)
scriptName=$(basename $0)
hostname=$(hostname)
# Base à backuper
baseToBackup="$1"
# Répertoire de sauvergarde des dump SQL
backupLocation="/home/sqldump"
# Nom du backup
dataName="databasebackup-$(date +%d.%m.%y@%Hh%M)"
# Répertoire temporaire
dataTmp="${backupLocation}/temp"
# Mail pour l'envoi du rapport
mailAdmin="monmail@test.com"
# Version du script
scriptVersion="1.0"
# Les logs
logsLocation="/var/log/sqlite-backup"
logOut="${logsLocation}/out.log"
logCumul="${logsLocation}/sqlite-backup.log"
dateOfThisDay=$(date)
# Initialisation signal erreur 
error=0
# Sqlite2SQL
sqliteSqlParser="sqlite_sql_parser.py"
sqliteSqlParserGit="https://raw.githubusercontent.com/motherapp/sqlite_sql_parser/master/parse_sqlite_sql.py"
 
if [ `whoami` != 'root' ]
	then
	echo "Ce script doit être utilisé par le compte root. Utilisez SUDO."
	exit 1
fi

[ -z $1 ] && echo "Vous devez entrer en argument le chemin du fichier de base Sqlite à backuper." && exit 1

umask 027

## Redirection des sorties vers nos logs : création des dossiers nécessaires
if [ ! -d ${logsLocation} ]; then
    mkdir -p ${logsLocation}
    [ $? -ne 0 ] && error=1 && echo "*** Problème pour créer le dossier ${logsLocation} ***" && echo "Il sera impossible de journaliser le processus."
fi
if [ ! -d ${backupLocation} ]; then
    mkdir -p ${backupLocation} 
    [ $? -ne 0 ] && echo "*** Problème pour créer le dossier ${backupLocation} ***" && echo "Il est impossible de poursuivre la sauvegarde." && exit 1
fi

# Suppression des anciens logs temporaires
[ -f ${logOut} ] && rm ${logOut}

# Ouverture de notre fichier de log 
echo "" >> ${logOut}
echo "****************************** $dateOfThisDay ******************************" >> ${logOut}
echo "" >> ${logOut}
echo "Machine : " $hostname >> ${logOut}
echo "" >> ${logOut}

[ ! -f ${baseToBackup} ] && echo "*** Le fichier Sqlite ${baseToBackup} n'est pas correct ***" && echo "Il est impossible de poursuivre la sauvegarde." && exit 1

cd ${backupLocation}
[ $? -ne 0 ] && echo "*** Problème pour accéder au dossier ${backupLocation} ***" && echo "Il est impossible de poursuivre la sauvegarde." && exit 1
 
## En fonction du jour, changement du nombre de backup à garder et du répertoire de destination
if [ "$( date +%w )" == "0" ]; then
        [ ! -d dimanche ] && mkdir -p dimanche
        dataDir=${backupLocation}/dimanche
         # Période en jours de conservation des DUMP hebdomadaires
        keepNumber=56
        echo "Backup hebdomadaire, ${keepNumber} jours d'ancienneté seront gardés." >> ${logOut}
else
        [ ! -d quotidien ] && mkdir -p quotidien
        dataDir=${backupLocation}/quotidien
        # Période en jours de conservation des DUMP quotidiens
        keepNumber=14
        echo "Backup quotidien, ${keepNumber} jours d'ancienneté seront gardés." >> ${logOut}
fi
 
## Création d'un répertoire temporaire pour la sauvegarde avant de zipper l'ensemble des dumps
mkdir -p ${dataTmp}/${dataName}
[ $? -ne 0 ] && error=1 && echo "*** Problème pour créer le dossier ${dataTmp}/${dataName} ***" >> ${logOut}
 
# Dump de la base
sqlite3 ${baseToBackup} .dump > ${dataTmp%/}/${dataName%/}/$(basename ${baseToBackup}).dump
[ $? -ne 0 ] && error=1 && echo "*** Problème pour réaliser le dump ***" >> ${logOut}

## On prépare les SQL avec le parser
cd ${currentDir%/}
[[ -e ${currentDir%/}/${sqliteSqlParser} ]] && rm ${currentDir%/}/${sqliteSqlParser}
curl --insecure ${sqliteSqlParserGit} -o ${currentDir%/}/${sqliteSqlParser} > /dev/null 2>&1
[ $? -ne 0 ] && error=1 && echo "*** Problème pour installer ${sqliteSqlParser} avec curl ***" >> ${logOut}
chmod +x ${currentDir%/}/${sqliteSqlParser}

cd ${dataTmp%/}/${dataName%/}/
echo "" >> ${logOut}
echo "Traitement du dump avec ${currentDir%/}/${sqliteSqlParser} :"  >> ${logOut}
python ${currentDir%/}/${sqliteSqlParser} $(basename ${baseToBackup}).dump  >> ${logOut}
[ $? -ne 0 ] && error=1 && echo "*** Problème pour traiter le dump avec ${sqliteSqlParser} ***" >> ${logOut}

## On commpresse (TAR) tous et on créé un lien symbolique pour le dernier
cd ${dataTmp}
echo "" >> ${logOut}
echo "Création de l'archive ${dataDir}/${dataName}.sqlite.gz" >> ${logOut}
tar -czf ${dataDir}/${dataName}.sqlite.gz ${dataName}
[ $? -ne 0 ] && error=1 && echo "*** Problème lors de la création de l'archive ${dataDir}/${dataName}.sqlite.gz ***" >> ${logOut}
cd ${dataDir}
chmod 600 ${dataName}.sqlite.gz
[ -f last.sqlite.gz ] &&  rm last.sqlite.gz
ln -s ${dataDir}/${dataName}.sqlite.gz ${dataDir}/last.sqlite.gz
 
## On supprime le répertoire temporaire
 [ -d ${dataTmp}/${dataName} ] && rm -rf ${dataTmp}/${dataName}
 
## On supprime les anciens backups
echo "" >> ${logOut}
echo "Suppression des vieux DUMP éventuels" >> ${logOut}
find ${dataDir%/} -name "*.sqlite.gz" -mtime +${keepNumber} -print -exec rm {} \; >> ${logOut}
[ $? -ne 0 ] && error=1
 
## Envoi d'un email de notification
if [ $error -ne 0 ]
    then
        echo "" >> ${logOut}
        echo "Problème lors de l'éxécution de (${0}). Merci de corriger le processus." >> ${logOut}
        mail -s "[FAILED] Rapport Dump MySql (${0})" ${mailAdmin} < "${logOut}"
    else
        echo "" >> ${logOut}
        echo "Script de dump des bases MySql (${0}) exécuté avec succès."  >> ${logOut}
        mail -s "[OK] Rapport Dump MySql (${0})" ${mailAdmin} < "${logOut}"
fi
 
cat ${logOut} >> ${logCumul}
[ -f ${logOut} ] && rm  ${logOut}

[ ${error} -ne 0 ] && exit 1

exit 0
