#!/bin/bash
#Usage: ./Expanded_NVMe_FIO.sh

#read -p "Which drive should benchmark use? Existing data will be lost! [default 'nvme0n1']: " NVMEDRIVE
#NVMEDRIVE=${NVMEDRIVE:-'nvme10n1'}

NVMEDRIVE=$1
echo "Benchmark Drive: $NVMEDRIVE"

testpath=/dev/$NVMEDRIVE
echo $testpath

drive_name=`sudo nvme id-ctrl $testpath | awk '$1=="subnqn" {print $3}' | cut -d ':' -f 3 | xargs`
server_model=`sudo dmidecode -t1 | grep 'Product Name:' | xargs | cut -d ':' -f 2 | xargs | tr " " - | xargs`
cpu_model=`sudo cat /proc/cpuinfo | grep 'model name' | uniq | cut -d ':' -f 2 | xargs | tr " " - | tr "@" a | tr "(" - | tr ")" - | xargs`
serial_num=`nvme id-ctrl $testpath | awk '$1=="sn" {print $3}'`
model_num=`nvme id-ctrl $testpath | awk '$1=="mn" {print $3, $4, $5, $6, $7}' | xargs | tr " " - | xargs`
fw_rev=`nvme id-ctrl $testpath | awk '$1=="fr" {print $3}'`
cap_Bytes=`nvme id-ctrl $testpath | awk '$1=="tnvmcap" {print $3}'`
TB_multiplier=1000000000000
echo "Drive Name: $drive_name"
echo "Server: $server_model"
echo "CPU: $cpu_model"
echo "Serial Num: $serial_num"
echo "Model Num: $model_num"
echo "FW_REV: $fw_rev"
echo "Cap Bytes: $cap_Bytes"


cap_TB=$(($cap_Bytes / $TB_multiplier))
cap_TB=$((cap_TB+1))

num_loops=2
iosize=$(($cap_TB * $num_loops * 1000))

date=$(date '+%m-%d-%Y')
timestamp=$(date +'%T')
result_dir=`echo "${drive_name}_${model_num}_${serial_num}_${fw_rev}_${date}_${timestamp}_${cpu_model}_${server_model}" | xargs`
telemetry_dir="Telemetry_Logs"
run_output_dir="Run_Output"
rand_output_dir="Random"
seq_output_dir="Sequential"
outputcsv_dir="output_csv"


if [ -d ${result_dir} ]
then
    echo "Directory ${result_dir} exists." 
    exit 0
else
    mkdir ${result_dir}
fi

cd ${result_dir}

mkdir ${telemetry_dir}
cd ${telemetry_dir}

echo "Getting telemetry log prior to running workload started at"
date
nvme telemetry-log /dev/$NVMEDRIVE --output-file=${model_num}_telemetry_${date}_before_workload

echo "Getting telemetry log prior to running workload completed at"
date

echo "Formatting drive started at"
date
nvme format /dev/$NVMEDRIVE --ses=1 --force
echo "Formatting completed at"
date

cd ..

mkdir ${run_output_dir}
cd ${run_output_dir}

mkdir ${outputcsv_dir}

mkdir ${rand_output_dir}
mkdir ${seq_output_dir}

#ioengine
ioeng="libaio"

#run type
run_type="terse"

#bs
rnd_block_size=(4k 8k 16k 32k 64k 128k 512k 1024k)
seq_block_size=(128k 512k 1024k)

#numjobs
rnd_qd=(1 8 16 32 64 128 256)
seq_qd=(1)

#percentile_list
perc_list="99:99.9:99.99:99.999:99.9999:100"

#read write percentages
rd_wr_perc=(0 30 50 70 100)

cd ${rand_output_dir}

# RANDOM BS WORKLOAD ONLY
for bs in "${rnd_block_size[@]}"; do

mkdir ${bs}
cd ${bs}

echo "Sequential preconditioning for bs=128k started at"
date
echo "workload:fio --direct=1 --rw=write  --bs=128k --iodepth=256 --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --name=Seq_precondition_bs128k_qd256_t1 --group_reporting --filename=/dev/$NVMEDRIVE  --output-format=terse --loops=3"
fio --direct=1 --rw=write  --bs=128k --iodepth=256 --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --name=Seq_precondition_bs128k_qd256_t1 --group_reporting --filename=/dev/$NVMEDRIVE  --output-format=terse --loops=3
echo "workload independent preconditioning done at"
date

echo "Random preconditioning for bs=${bs} started at"
date
echo "workload:fio --direct=1 --rw=randwrite  --bs=${bs} --iodepth=256 --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --name=Ran_precondition_bs${bs}_qd256_t1 --group_reporting --filename=/dev/$NVMEDRIVE  --output-format=terse --loops=3"
fio --direct=1 --rw=randwrite  --bs=${bs} --iodepth=256 --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --name=Ran_precondition_bs${bs}_qd256_t1 --group_reporting --filename=/dev/$NVMEDRIVE  --output-format=terse --loops=3
echo "workload independent preconditioning done at"
date

for perc in "${rd_wr_perc[@]}"; do 

rd_perc=${perc}
wr_perc="$((100-${rd_perc}))"

for qd in "${rnd_qd[@]}"; do

if [ ${qd} -eq 1 ]
then
    echo "Random Mixed ${rd_perc}% Read ${wr_perc}% Write bs=${bs} t1 qd${qd}"
    date
    echo "fio --time_based --runtime=300 --output-format=${run_type} --direct=1 --buffered=0 --rw=randrw --rwmixread=${rd_perc} --rwmixwrite=${wr_perc} --bs=${bs} --iodepth=${qd} --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --group_reporting --percentile_list=${perc_list} --name=randmixedread${rd_perc}write${wr_perc}_${ioeng}_t1_qd${qd}_bs${bs} --filename=/dev/$NVMEDRIVE --output=${result_dir}-randmixedread${rd_perc}write${wr_perc}-bs${bs}-threads1-depth${qd}"
    fio --time_based --runtime=300 --output-format=${run_type} --direct=1 --buffered=0 --rw=randrw --rwmixread=${rd_perc} --rwmixwrite=${wr_perc} --bs=${bs} --iodepth=${qd} --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --group_reporting --percentile_list=${perc_list} --name=randmixedread${rd_perc}write${wr_perc}_${ioeng}_t1_qd${qd}_bs${bs} --filename=/dev/$NVMEDRIVE --output=${result_dir}_randmixedread${rd_perc}write${wr_perc}-bs${bs}-threads1-depth${qd}
    date
else
    echo "Random Mixed ${rd_perc}% Read ${wr_perc}% Write bs=${bs} t8 qd${qd}"
    date
    echo "fio --time_based --runtime=300 --output-format=${run_type} --direct=1 --buffered=0 --rw=randrw --rwmixread=${rd_perc} --rwmixwrite=${wr_perc} --bs=${bs} --iodepth=${qd} --ioengine=${ioeng} --numjobs=8 --norandommap=1 --randrepeat=0 --group_reporting --percentile_list=${perc_list} --name=randmixedread${rd_perc}write${wr_perc}_${ioeng}_t8_qd${qd}_bs${bs} --filename=/dev/$NVMEDRIVE --output=${result_dir}-randmixedread${rd_perc}write${wr_perc}-bs${bs}-threads8-depth${qd}"
    fio --time_based --runtime=300 --output-format=${run_type} --direct=1 --buffered=0 --rw=randrw --rwmixread=${rd_perc} --rwmixwrite=${wr_perc} --bs=${bs} --iodepth=${qd} --ioengine=${ioeng} --numjobs=8 --norandommap=1 --randrepeat=0 --group_reporting --percentile_list=${perc_list} --name=randmixedread${rd_perc}write${wr_perc}_${ioeng}_t8_qd${qd}_bs${bs} --filename=/dev/$NVMEDRIVE --output=${result_dir}_randmixedread${rd_perc}write${wr_perc}-bs${bs}-threads8-depth${qd}
    date
fi

done 

done

cd ..

for file in ${bs}/*
do
  cat "$file" >> ${bs}_output.csv
done 
mv ${bs}_output.csv /home/labuser/${result_dir}/${run_output_dir}/${outputcsv_dir}/

sudo python3 /home/labuser/database_insert.py fio_expanded ${bs}/

done



cd ..

cd ${seq_output_dir}

# SEQUENTIAL BS WORKLOAD ONLY
for bs in "${seq_block_size[@]}"; do

mkdir ${bs}
cd ${bs}

echo "Sequential preconditioning for bs=${bs} started at"
date
echo "workload:fio --direct=1 --rw=write  --bs=${bs} --iodepth=256 --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --name=Seq_precondition_bs${bs}_qd256_t1 --group_reporting --filename=/dev/$NVMEDRIVE  --output-format=terse --loops=3"
fio --direct=1 --rw=write  --bs=${bs} --iodepth=256 --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --name=Seq_precondition_bs${bs}_qd256_t1 --group_reporting --filename=/dev/$NVMEDRIVE  --output-format=terse --loops=3
echo "workload independent preconditioning done at"
date

for perc in "${rd_wr_perc[@]}"; do 

rd_perc=${perc}
wr_perc="$((100-${rd_perc}))"

for qd in "${seq_qd[@]}"; do

echo "Sequential Mixed ${rd_perc}% Read ${wr_perc}% Write bs=${bs} t1 qd${qd}"
date
echo "fio --time_based --runtime=300 --output-format=${run_type} --direct=1 --buffered=0 --rw=rw --rwmixread=${rd_perc} --rwmixwrite=${wr_perc} --bs=${bs} --iodepth=${qd} --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --group_reporting --percentile_list=${perc_list} --name=seqmixedread${rd_perc}write${wr_perc}_${ioeng}_t1_qd${qd}_bs${bs} --filename=/dev/$NVMEDRIVE --output=${result_dir}-seqmixedread${rd_perc}write${wr_perc}_-bs${bs}-threads1-depth${qd}"
fio --time_based --runtime=300 --output-format=${run_type} --direct=1 --buffered=0 --rw=rw --rwmixread=${rd_perc} --rwmixwrite=${wr_perc} --bs=${bs} --iodepth=${qd} --ioengine=${ioeng} --numjobs=1 --norandommap=1 --randrepeat=0 --group_reporting --percentile_list=${perc_list} --name=seqmixedread${rd_perc}write${wr_perc}_${ioeng}_t1_qd${qd}_bs${bs} --filename=/dev/$NVMEDRIVE --output=${result_dir}_seqmixedread${rd_perc}write${wr_perc}-bs${bs}-threads1-depth${qd}
date

done

done

cd ..

for file in ${bs}/*
do
  cat "$file" >> ${bs}_output.csv
done 
mv ${bs}_output.csv /home/labuser/${result_dir}/${run_output_dir}/${outputcsv_dir}/

sudo python3 /home/labuser/database_insert.py fio_expanded ${bs}/

done

cd ..

cd ..

cd ${telemetry_dir}

echo "Getting telemetry log after running workload started at"
date
nvme telemetry-log /dev/$NVMEDRIVE --output-file=${model_num}_telemetry_${date}_after_workload

echo "Getting telemetry log after running workload completed at"
date

cd ..

echo "Results are in $result_dir"

exit
