#!/bin/bash
#(Uniquement pour le WSL,) Si vous voulez sélectionner le moteur par défaut (même pendant un batch), enlevez le "sudo" aux lignes 39, 44, 49 et 52.
#Si vous n'utilisez pas WSL, "sudo" peut causer des erreurs. Enlevez le!
#prout
get_sourcename (){ #putain de fonction qui sépare l'extension du fichier vidéo de son nom.
	sourcename=$1
	sourcename=${sourcename%".mp4"}
	sourcename=${sourcename%".mkv"}
	sourcename=${sourcename%".flv"}
	fname=$sourcename
}
get_type (){ #autre fonction de merde permettant de détecter si l'argument d'entrée spécifier correspond a un dossier ou a un fichier
	inputstr=$1
	propstr=$((${#inputstr}-1))
	if [[ ${inputstr:$propstr:1} == "/" ]]; then
		ftype="folder"
	else
		ftype="file"
	fi
}	
do_fcheck(){ #check de l'existence de l'argument d'entrée
	if [[ $1 == "folder" ]]; then
		if [[ ! -d $2 ]]; then
			echo "Le répertoire $2 n'existe pas!"
			exit 1
		fi
	elif [[ $1 == "file" ]]; then
		if ! test -f "$2"; then
			echo "Le fichier $2 n'existe pas"
			exit 1
		fi
	fi
}

ocr(){ #ocr (commentez la première ligne du fichier YoloCR.vpy)
case $2 in
	"lstm" ) echo "Utilisation du moteur LSTM";	#actions pour le moteur lstm
		vspipe -y --arg FichierSource="$1" YoloCR.vpy - | ffmpeg -i - -c:v mpeg4 -qscale:v 3 -y output_filtered.mp4;
		mv tessdata/fra.traineddata tessdata/fra.traineddata.no 2>/dev/null;
		sudo bash YoloCR.sh output_filtered.mp4 fra;
		regex;
		post_ocr $1;;
	"legacy" ) echo "Utilisation du moteur Legacy"; #actions pour le moteur legacy
		vspipe -y --arg FichierSource="$1" YoloCR.vpy - | ffmpeg -i - -c:v mpeg4 -qscale:v 3 -y output_filtered.mp4;
		mv tessdata/fra.traineddata.no tessdata/fra.traineddata 2>/dev/null; 
		sudo bash YoloCR.sh output_filtered.mp4 fra;
		regex;
		post_ocr $1;;
	"both" ) echo "Utilisation des moteurs LSTM et Legacy";	#actions pour les 2 moteurs ainsi que la combinaison des fichiers
		vspipe -y --arg FichierSource="$1" YoloCR.vpy - | ffmpeg -i - -c:v mpeg4 -qscale:v 3 -y output_filtered.mp4;
		mv tessdata/fra.traineddata.no tessdata/fra.traineddata 2>/dev/null;
		sudo bash YoloCR.sh output_filtered.mp4 fra;
		mv output_filtered.srt output_legacy.srt;
		mv tessdata/fra.traineddata tessdata/fra.traineddata.no 2>/dev/null;
		sudo bash YoloCR.sh output_filtered.mp4 fra;
		italics output_legacy.srt output_filtered.srt; #petite magie
		regex;
		post_ocr $1;;
	*) echo "Veuillez sélectionner un moteur: lstm | legacy | both"; exit 1;; #ca quitte pck vous lisez pas
esac
}

regex(){
	echo "Corrections de toutes les erreurs relatives au moteur OCR..."
	sed -i 's|? |?|g' output_filtered.srt
	sed -i 's|?|? |g' output_filtered.srt
	sed -i 's|ca |ça |g' output_filtered.srt
	sed -i 's|Ca |Ça |g' output_filtered.srt
	sed -i 's|lI|ll|g' output_filtered.srt
	sed -i 's| dela | de la |g' output_filtered.srt
	sed -i 's| àla | à la |g' output_filtered.srt
	sed -i 's| tele | te le |g' output_filtered.srt
	sed -i 's|\./…|…|g' output_filtered.srt

	read -p 'Voulez vous procéder au check manuel des erreurs d’OCR? y/n: ' ansvar
	if [[ $ansvar == "y" ]]; then
		aspell --lang=fr check output_filtered.srt
	fi
}


post_ocr(){ #actions de post-ocr

	#une saloperie de caractère peut s'interposer alors on le vire au cas où
	echo "Suppresion des caractères illégaux dans le fichier final..." 
	while read a; do
		echo ${a///}
	done < output_filtered.srt > output_filtered.srt.tmp
	mv output_filtered.srt{.tmp,}

	#on dégage tout les gros fichiers après l'ocr pour faire de la place et avoir un répertoire propre
	echo "Suppressions des fichiers et dossiers temporaires..."		
	get_sourcename $1
	mv output_filtered.srt $fname.srt
	rm -f output_filtered.mp4 $1.ffindex Timecodes.txt SceneChanges.log
	rm -Rf ScreensFiltrés TessResult
	echo "$1 Terminé"
}

italics(){ #algo de transfer de balises italiques
	totallines=$(cat $1 | wc -l)
	sublines=1
	for ((lines=1; lines<=totallines; lines++)); do
		if [[ $(sed -n "$lines"p $1) == "$sublines" ]]; then
			if [[ $(sed -n $((lines+3))p $1) == "" ]]; then
					twolines="false"
				else
					twolines="true"
			fi
			if [[ $(sed -n $((lines+2))p $1) == *"<i>"* ]]; then
					italic="true"
				else
					italic="false"
			fi
		fi
		if [[ $(sed -n "$lines"p $2) == "$sublines" ]]; then #check indépendant des fichiers pour éviter les erreurs
			if [[ $italic == "true" ]]; then
				echo "Ajout de l'italique à $sublines"
				sed -i ''$((lines+2))'s/^/<i>/' $2
				if [[ $twolines == "true" ]]; then
						sed -i ''$((lines+3))'s|$|</i>|' $2
					else
						sed -i ''$((lines+2))'s|$|</i>|' $2
				fi
			fi 
		((sublines++))	
		fi
	done
	rm -f $1 #suppression du srt legacy
}

#Vérifications pré-utilisation
if (( $EUID == 0 )); then #check de l'éxécution
	echo "Ce script ne dois pas être exécuté en tant que 'root'!"
	exit
elif [ -z "$1" ]; then #check de l'argument
	echo -e "Veuillez spécifier un fichier ou un répertoire en entrée ainsi que le type de moteur.\nExemple: ./OCR.sh input.mp4 lstm\nExemple: ./OCR.sh mesvideos/ legacy"
	exit
fi
if [[ $1 == "install" ]]; then
	echo "Installation des dernières traineddata en date pour les moteurs LSTM et Legacy"
	wget https://github.com/tesseract-ocr/tessdata_best/raw/master/fra.traineddata
	sudo mv -f fra.traineddata /usr/share/tesseract-ocr/4.00/tessdata/fra.traineddata
	wait
	wget https://github.com/tesseract-ocr/tessdata/raw/master/fra.traineddata
	mv -f fra.traineddata tessdata/fra.traineddata
	echo "Installation du correcteur d'orthographe..."
	sudo apt-get install aspell aspell-fr
	exit
fi

get_type $1 #test du type d'entrée
do_fcheck $ftype $1 #test de l'existence de l'entrée

if [[ $ftype == "folder" ]]; then
		echo $1
		for file in "$1"*.{mp4,mkv,flv}; do #StackOverflow 200% j'ai juste eu de la chance que ça ait marché direct mdr
			[ -f "$file" ] || break
			echo "$file"
			ocr $file $2			
		done
		echo "C'est fini chef!" #Ca a été vachement long alors on est gentil est on met un petit message :)
elif [[ $ftype == "file" ]]; then
	ocr $1 $2
fi