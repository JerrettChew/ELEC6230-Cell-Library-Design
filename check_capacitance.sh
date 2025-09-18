cell="nand3"
globallist=( Vdd! GND! )
inlist=( A B C )
outlist=( Y )
COut="1fF"

# inputs $1 input line
#        $2 input file
#        $3 starting from line number
find_line_num_in_file () {
  eval in_line="$1"
  eval in_file="$2"
  eval line_num="$3"
  
  #debug inputs
  #echo $in_line >&2
  #echo $in_file >&2
  #echo $line_num >&2
  #echo "---" >&2
  
  # get tail of file starting from line number $1 |
  # line number of find "in_line" in the file
  local line=$(tail -n +$(("$line_num" + 1)) "$in_file" | grep -n "$in_line" | cut -d : -f 1)
  echo $line
}

echo "cell: $cell"
echo "global: ${globallist[*]}"
echo "in: ${inlist[*]}"
echo "out: ${outlist[*]}"
echo "output capacitance: $COut"

ext2sp -f $cell > /dev/null

# get scaling option from file
n=$(find_line_num_in_file "scale=" $cell.spice 0)
scale=$(sed -n "${n}p" $cell.spice)

# convert .spice into a subcircuit
sed -i "2i .SUBCKT $cell ${outlist[*]} ${inlist[*]} Vdd GND" $cell.spice
n=$(wc -l $cell.spice | cut -d " " -f 1)
sed -i "${n}i .ENDS $cell" $cell.spice

# find supply voltage to be used
n=$(find_line_num_in_file "Vsupply" $cell.sp 0)
Vsupply=$(sed -n "${n}p" $cell.sp | cut -d " " -f 4)
Vsupply=${Vsupply::-1}

cp $cell.sp ${cell}_temp.sp

for(( i=0; i<${#inlist[@]}; i++)); do
  for(( j=0; j<${#outlist[@]}; j++)); do
    cp ${cell}_temp.sp $cell.sp
    echo "Finding propagation delay for ${inlist[i]} > ${outlist[j]}"
    
    # insert circuit to be simulated
    n=$(find_line_num_in_file "Vsupply" $cell.sp 0)
    sed -i "$((n + 2))i **Capacitance Simulation\n" $cell.sp
    sed -i "$((n + 3))i $scale" $cell.sp
    sed -i "$((n + 4))i X${cell}_driver ${outlist[*]} ${inlist[*]} Vdd GND $cell" $cell.sp
    sed -i "$((n + 5))i Ctest GND ${outlist[$j]} $COut" $cell.sp
    
    # insert input signals
    #input="V$k ${inlist[$k]} GND PWL(0NS ${Vsupply}V)"
    #input="V3 C GND PWL(0NS ${Vsupply}V)"
    #sed -i "$((n+k+4))i $input1" $cell.sp
    #sed -i "$((n+5))i $input2" $cell.sp
    #sed -i "$((n+6))i $input3" $cell.sp
    line="Specify input signals here"
    n=$(find_line_num_in_file $\line $cell.sp 0)
    for(( k=0; k<${#inlist[@]}; k++)); do
      input="V$k ${inlist[$k]} GND PWL(0NS ${Vsupply}V)"
      sed -i "$((n+k+4))i $input" $cell.sp
    done
    
    # change input to the one active
    line="V$i"
    n=$(find_line_num_in_file $line $cell.sp 0)
    input="V$i ${inlist[$i]} GND PWL(0NS 0V  2NS 0V  2.25NS ${Vsupply}V  6NS ${Vsupply}V  6.25NS 0V)"
    sed -i "${n}s/.*/$input/" $cell.sp
    #input1="V1 A GND PWL(0NS 0V  2NS 0V  2.25NS ${Vsupply}V  6NS ${Vsupply}V  6.25NS 0V)"
    
    # insert simulation measurements
    line="Save results for display"
    n=$(find_line_num_in_file $\line $cell.sp 0)
    n=$((n - 1))

    measure1=".measure TRAN tdrr   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=0NS RISE=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=0NS RISE=1"
    measure2=".measure TRAN tdrf   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=0NS RISE=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=0NS FALL=1"
    measure3=".measure TRAN tdfr   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=4NS FALL=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=4NS RISE=1"
    measure4=".measure TRAN tdff   TRIG v(${inlist[i]}) VAL='0.5*$Vsupply' TD=4NS FALL=1 \n+TARG v(${outlist[j]}) VAL='0.5*$Vsupply' TD=4NS FALL=1"
    sed -i "${n}i $measure1" $cell.sp
    sed -i "$((n+2))i $measure2" $cell.sp
    sed -i "$((n+4))i $measure3" $cell.sp
    sed -i "$((n+6))i $measure4" $cell.sp
    
    #cat $cell.sp
    
    # run simulation
    hspice $cell.sp $cell.spice >> /dev/null
    echo "Running simulation | in: ${inlist[i]} | out: ${outlist[j]}"
    cat $cell.mt0
  done
done

