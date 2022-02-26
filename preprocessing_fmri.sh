#!/bin/bash

# stop if error
set -e

usage()
{
cat << EOF

usage: $0 [options]

sanbos FSL 5.0 preprocessing script for movinn fMRI data.

OPTIONS:
   -h      show this message
   -r      run name, will be used as folder name for output
   -d 	   data type: train or test
   -t      EPI volume repetition time (TR) in seconds
   -p      root folder for processed data

example: 
sh preproc_movinn_func_train.sh -r run002 -d train -t 0.7 -p /scratch/users/sanbos/_movinn/data

Alternatively, you may run this script without options and 
define all the required inputs as environmental variables.

Written by Sander E. Bosch (2018)

EOF
}

# input handling
if [ -n "$1" ];
then 
    runName=
    dataType=
    trInSec=
    procPath=
    while getopts "hd:r:d:t:p:" OPTION
    do
	case $OPTION in
            h)
		usage
		exit 1
		;;
            r)
		runName=$OPTARG		
		;;
            d)
		dataType=$OPTARG
		;;
            t)
		trInSec=$OPTARG
		;;
            p)
		procPath=$OPTARG
		;;
            ?)
		usage
		exit
		;;
	esac
    done
else echo "using environmental variables:"
    echo -e "\t -r $runName" 
    echo -e "\t -d $dataType"
    echo -e "\t -t $trInSec"
    echo -e "\t -p $procPath"
fi

if [ -z $runName ] || [ -z $dataType ] || [ -z $trInSec ] || [ -z $procPath ]
then
    echo "*** incorrect usage, required variables are not defined"
    usage
    exit 1
fi

# highpass filter settings
hpFilterCutoffInSec=50 #FWHM

# packages
fslPath=/scratch/users/sanbos/tools/fsl/bin

# directories
preprocDir=$procPath/preproc
structDir=$preprocDir/struct
niiDir=$preprocDir/func/${dataType}/nii
funcDir=$preprocDir/func/${dataType}/${runName}
funcRefRun001=$preprocDir/func/train/run001/example_func_brain_run001
diagDir=$procPath/preproc/diagnostics

if [ ! -d $diagDir ] 
	then mkdir $diagDir -p
fi

############################################
#####  START FUNCTIONAL PREPROCESSING  #####
############################################

if [ ! -e $funcDir/func_done ]
	then printf "preprocessing ${runName}_${dataType}\n"


	if [ ! -d $funcDir ] 
		then mkdir $funcDir -p
	fi
	cd $funcDir

	epiFile=$niiDir/${runName}.nii

	nVolumes=$($fslPath/fslinfo $epiFile | grep 'dim4' -m 1 | awk '{print $2}')
	midVolume=$((nVolumes/2))
 	
 	# example functional (volume number: ${midVolume})
	$fslPath/fslroi $epiFile example_func $midVolume 1
	
	# example functional brain extraction	
	$fslPath/bet example_func example_func_brain -f .3
	
	# estimate motion correction to example_func 
	$fslPath/mcflirt -in $epiFile -out r${runName} -plots -reffile example_func -rmsrel -rmsabs

	# motion correction diagnostics
	$fslPath/fsl_tsplot -i r${runName}.par -t 'MCFLIRT estimated rotations (radians)' -u 1 --start=1 --finish=3 -a x,y,z -w 640 -h 144 -o mc_rot.png
	$fslPath/fsl_tsplot -i r${runName}.par -t 'MCFLIRT estimated translations (mm)' -u 1 --start=4 --finish=6 -a x,y,z -w 640 -h 144 -o mc_trans.png
	$fslPath/fsl_tsplot -i r${runName}_abs.rms,r${runName}_rel.rms -t 'MCFLIRT estimated mean displacement (mm)' -u 1 -w 640 -h 144 -a absolute,relative -o mc_disp.png
	$fslPath/pngappend mc_rot.png - mc_trans.png - mc_disp.png $diagDir/${runName}_${dataType}_mc.png
	
	# estimate motion correction from example_func of current run to example_func of run 1
	$fslPath/flirt -in example_func_brain -ref $funcRefRun001 -out example_func2run001.nii -dof 6 -omat example_func2run001.mat
		
	# move run to example_func from run001
	$fslPath/applyxfm4D r${runName} $funcRefRun001 r${runName} example_func2run001.mat -singlematrix	

	#hpFilterSigma=[$hpFilterCutoffInSec/$trInSec]/2 #HWHM in volumes
	#$fslPath/fslmaths r${runName} -bptf $hpFilterSigma 0 fr${runName}
	
	# get mean functional
	$fslPath/fslmaths r${runName} -Tmean mean_r${runName}	
	
	# cleanup
	#printf "\t cleanup\n"
	rm mc_*.png
	touch func_done
fi

printf "${runName}_${dataType} preprocessing DONE\n"
