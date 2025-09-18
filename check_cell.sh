comb=("inv" "nand" "nor" "and" "or" "xor" "xnor")
declare -A gray_bin_mat
n=3
num_rows=$((2 ** $n))
num_columns=$n

generate_truth_table () {
  pow=$((2 ** $1))
  
  for ((j=0;j<$pow;j++)); do
    local n=$j
    
    #convert number to binary array 
    for ((k=0;k<$1;k++)); do
      bin=$(( ( $n & ( 1 << $k ) ) >> $k ))
      
      #store in matrix
      gray_bin_mat[$j,$(($1-$k-1))]=${bin}
    done
  done
}

generate_gray_code () {
  pow=$((2 ** $1))
  
  # gray(n) = n xor n>>1
  for ((j=0;j<$pow;j++)); do
    gray=$(( $j ^ $j >> 1 ))
    
    #convert number to binary array 
    for ((k=0;k<$1;k++)); do
      gray_bin=$(( ( $gray & ( 1 << $k ) ) >> $k ))
      
      #store in matrix
      gray_bin_mat[$j,$(($1-$k-1))]=${gray_bin}
    done
  done
}

print_gray_mat () {
  for ((i=0;i<$1;i++)); do
    out=""
    for ((j=0;j<$2;j++)); do
        out+="${gray_bin_mat[$i,$j]} "
    done
  echo $out
  done
}

generate_comb_gray_mat () {
  local cell=$1
  local num=$2
  local pow=$((2 ** $num))
  
  #determine edge cases
  if [[ $cell == "inv" ]]; then
    num=1
  fi
  
  echo "truth table matrix: $num $pow"
  generate_truth_table $num
  print_gray_mat $((2**$num)) $num
  
  # generate gray code input matrix
  gray_bin_mat=()
  echo "generating gray: $num $pow"
  generate_gray_code $num
    
  # generate output for each set of inputs and gate
  case $cell in
  inv)
    echo "inv" 
    
    for ((i=0;i<$pow;i++));do
      gray_bin_mat[$i,1]=$(( ! gray_bin_mat[$i,0] ))
    done
    ;;
  nand)
    echo "nand"
    
    for ((i=0;i<$pow;i++));do
      out=1
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out & $in ))
      done
      gray_bin_mat[$i,$num]=$(( ! $out ))
    done
    ;;
  nor)
    echo "nor"
    
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out | $in ))
      done
      gray_bin_mat[$i,$num]=$(( ! $out ))
    done
    ;;
  and)
    echo "and"
    
    for ((i=0;i<$pow;i++));do
      out=1
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out & $in ))
      done
      gray_bin_mat[$i,$num]=$out
    done
    ;;
  or)
    echo "or"
    
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out | $in ))
      done
      gray_bin_mat[$i,$num]=$out
    done
    ;;
  xor)
    echo "xor"
    
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out ^ $in ))
      done
      gray_bin_mat[$i,$num]=$out
    done
    ;;
  xnor)
    echo "xnor"
    
    for ((i=0;i<$pow;i++));do
      out=0
      for ((j=0;j<$num;j++));do 
        in=$((gray_bin_mat[$i,$j]))
        out=$(( $out ^ $in ))
      done
      gray_bin_mat[$i,$num]=$(( ! $out ))
    done
    ;;
  esac
}

# generate cell behaviour
for cell in ${comb[@]}; do
  generate_comb_gray_mat $cell $n
  
  print_gray_mat $((2**n)) $((n+1))
  
  for (( i=0; i<$n; i++ )); do
    bin=${gray_bin_mat[0,$i]}
    [[ $bin = 1 ]] && voltage="3.3" || voltage="0"
    prev_voltage=$voltage
    output="0NS ${voltage}V "
  
    for (( j=1; j<2**$n; j++ )); do
      bin=${gray_bin_mat[$j,$i]}
      [[ $bin = 1 ]] && voltage="3.3" || voltage="0"
      
      if [[ $prev != $bin ]]; then
        output+="$((j * 2 ))NS ${prev_voltage}V "
        output+="$((j * 2 )).25NS ${voltage}V "
      fi
      
      prev_voltage=$voltage
      prev=$bin
    done
    
    echo $output
  done
  echo "-------------------------"
done

# ----------------------------------
