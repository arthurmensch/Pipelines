#!/bin/bash
# Modified by Arthur Mensch to recompute StandardCoordinates statistics

set -e
g_script_name=`basename ${0}`

source ${HCPPIPEDIR}/global/scripts/log.shlib # Logging related functions
log_SetToolName "${g_script_name}"

source ${HCPPIPEDIR}/global/scripts/fsl_version.shlib # Function for getting FSL version

show_tool_versions()
{
	# Show HCP pipelines version
	log_Msg "Showing HCP Pipelines version"
	cat ${HCPPIPEDIR}/version.txt

	# Show fsl version
	log_Msg "Showing FSL version"
	fsl_version_get fsl_ver
	log_Msg "FSL version: ${fsl_ver}"
}

Subject="$1"
log_Msg "Subject: ${Subject}"

ResultsFolder="$2"
log_Msg "ResultsFolder: ${ResultsFolder}"

DownSampleFolder="$3"
log_Msg "DownSampleFolder: ${DownSampleFolder}"

LevelOnefMRINames="$4"
log_Msg "LevelOnefMRINames: ${LevelOnefMRINames}"

LevelOnefsfNames="$5"
log_Msg "LevelOnefsfNames: ${LevelOnefsfNames}"

LevelTwofMRIName="$6"
log_Msg "LevelTwofMRIName: ${LevelTwofMRIName}"

LevelTwofsfName="$7"
log_Msg "LevelTwofsfName: ${LevelTwofsfName}"

LowResMesh="$8"
log_Msg "LowResMesh: ${LowResMesh}"

FinalSmoothingFWHM="$9"
log_Msg "FinalSmoothingFWHM: ${FinalSmoothingFWHM}"

TemporalFilter="${10}"
log_Msg "TemporalFilter: ${TemporalFilter}"

VolumeBasedProcessing="${11}"
log_Msg "VolumeBasedProcessing: ${VolumeBasedProcessing}"

RegName="${12}"
log_Msg "RegName: ${RegName}"

Parcellation="${13}"
log_Msg "Parcellation: ${Parcellation}"

show_tool_versions

#Set up some things
LevelOnefMRINames=`echo $LevelOnefMRINames | sed 's/@/ /g'`
LevelOnefsfNames=`echo $LevelOnefsfNames | sed 's/@/ /g'`

if [ ! ${Parcellation} = "NONE" ] ; then
  ParcellationString="_${Parcellation}"
  Extension="ptseries.nii"
  ScalarExtension="pscalar.nii"
else
  ParcellationString=""
  Extension="dtseries.nii"
  ScalarExtension="dscalar.nii"
fi

log_Msg "ParcellationString: ${ParcellationString}"
log_Msg "Extension: ${Extension}"
log_Msg "ScalarExtension: ${ScalarExtension}"

if [ ! ${RegName} = "NONE" ] ; then
  RegString="_${RegName}"
else
  RegString=""
fi

log_Msg "RegString: ${RegString}"

SmoothingString="_s${FinalSmoothingFWHM}"
log_Msg "SmoothingString: ${SmoothingString}"

TemporalFilterString="_hp""$TemporalFilter"
log_Msg "TemporalFilterString: ${TemporalFilterString}"

LevelOneFEATDirSTRING=""
i=1
for LevelOnefMRIName in $LevelOnefMRINames ; do
  LevelOnefsfName=`echo $LevelOnefsfNames | cut -d " " -f $i`
  LevelOneFEATDirSTRING="${LevelOneFEATDirSTRING}${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}${TemporalFilterString}${SmoothingString}_level1${RegString}${ParcellationString}.feat "
  i=$(($i+1))
done
NumFirstLevelFolders=$(($i-1))

FirstFolder=`echo $LevelOneFEATDirSTRING | cut -d " " -f 1`
ContrastNames=`cat ${FirstFolder}/design.con | grep "ContrastName" | cut -f 2`
NumContrasts=`echo ${ContrastNames} | wc -w`
LevelTwoFEATDir="${ResultsFolder}/${LevelTwofMRIName}/${LevelTwofsfName}${TemporalFilterString}${SmoothingString}_level2${RegString}${ParcellationString}.feat"
if [ -e ${LevelTwoFEATDir} ] ; then
  rm -r ${LevelTwoFEATDir}
  mkdir ${LevelTwoFEATDir}
else
  mkdir -p ${LevelTwoFEATDir}
fi

cat ${ResultsFolder}/${LevelTwofMRIName}/${LevelTwofsfName}_hp200_s4_level2.fsf | sed s/_hp200_s4/${TemporalFilterString}${SmoothingString}${RegString}${ParcellationString}/g > ${LevelTwoFEATDir}/design.fsf

#Make design files
log_Msg "Make design files"
DIR=`pwd`
cd ${LevelTwoFEATDir}
feat_model ${LevelTwoFEATDir}/design
cd $DIR

#Loop over Grayordinates and Standard Volume (if requested) Level 2 Analyses
log_Msg "Loop over Grayordinates and Standard Volume (if requested) Level 2 Analyses"
if [ ${VolumeBasedProcessing} = "YES" ] ; then
  Analyses="StandardVolumeStats"
elif [ -z ${ParcellationString} ] ; then
  Analyses="GrayordinatesStats"
else
  Analyses="ParcellatedStats"
fi
log_Msg "Analyses: ${Analyses}"

for Analysis in ${Analyses} ; do
  log_Msg "Analysis: ${Analysis}"
  mkdir -p ${LevelTwoFEATDir}/${Analysis}

  #Copy over level one folders and convert CIFTI to NIFTI if required
  log_Msg "Copy over level one folders and convert CIFTI to NIFTI if required"
  if [ -e ${FirstFolder}/${Analysis}/cope1.nii.gz ] ; then
    Grayordinates="NO"
    i=1
    for LevelOneFEATDir in ${LevelOneFEATDirSTRING} ; do
      mkdir -p ${LevelTwoFEATDir}/${Analysis}/${i}
      cp ${LevelOneFEATDir}/${Analysis}/* ${LevelTwoFEATDir}/${Analysis}/${i}
      i=$(($i+1))
    done
  else
    echo "Level One Folder Not Found"
  fi

  #Create dof and Mask
  log_Msg "Create dof and Mask"
  MERGESTRING=""
  i=1
  while [ $i -le ${NumFirstLevelFolders} ] ; do
    dof=`cat ${LevelTwoFEATDir}/${Analysis}/${i}/dof`
    fslmaths ${LevelTwoFEATDir}/${Analysis}/${i}/res4d.nii.gz -Tstd -bin -mul $dof ${LevelTwoFEATDir}/${Analysis}/${i}/dofmask.nii.gz
    MERGESTRING=`echo "${MERGESTRING}${LevelTwoFEATDir}/${Analysis}/${i}/dofmask.nii.gz "`
    i=$(($i+1))
  done
  fslmerge -t ${LevelTwoFEATDir}/${Analysis}/dof.nii.gz $MERGESTRING
  fslmaths ${LevelTwoFEATDir}/${Analysis}/dof.nii.gz -Tmin -bin ${LevelTwoFEATDir}/${Analysis}/mask.nii.gz

  #Merge COPES and VARCOPES and run 2nd level analysis
  log_Msg "Merge COPES and VARCOPES and run 2nd level analysis"
  log_Msg "NumContrasts: ${NumContrasts}"
  i=1
  while [ $i -le ${NumContrasts} ] ; do
	log_Msg "i: ${i}"
    COPEMERGE=""
    VARCOPEMERGE=""
    j=1
    while [ $j -le ${NumFirstLevelFolders} ] ; do
      COPEMERGE="${COPEMERGE}${LevelTwoFEATDir}/${Analysis}/${j}/cope${i}.nii.gz "
      VARCOPEMERGE="${VARCOPEMERGE}${LevelTwoFEATDir}/${Analysis}/${j}/varcope${i}.nii.gz "
      j=$(($j+1))
    done
    fslmerge -t ${LevelTwoFEATDir}/${Analysis}/cope${i}.nii.gz $COPEMERGE
    fslmerge -t ${LevelTwoFEATDir}/${Analysis}/varcope${i}.nii.gz $VARCOPEMERGE
    flameo --cope=${LevelTwoFEATDir}/${Analysis}/cope${i}.nii.gz --vc=${LevelTwoFEATDir}/${Analysis}/varcope${i}.nii.gz --dvc=${LevelTwoFEATDir}/${Analysis}/dof.nii.gz --mask=${LevelTwoFEATDir}/${Analysis}/mask.nii.gz --ld=${LevelTwoFEATDir}/${Analysis}/cope${i}.feat --dm=${LevelTwoFEATDir}/design.mat --cs=${LevelTwoFEATDir}/design.grp --tc=${LevelTwoFEATDir}/design.con --runmode=fe
    i=$(($i+1))
  done

  #Cleanup Temporary Files
  log_Msg "Cleanup Temporary Files"
  j=1
  while [ $j -le ${NumFirstLevelFolders} ] ; do
    rm -r ${LevelTwoFEATDir}/${Analysis}/${j}
    j=$(($j+1))
  done
done
