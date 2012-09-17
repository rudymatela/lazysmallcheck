[ $# -ne 2 ] && echo "performance.sh: Expecting two arguments representing core.and identifier." && exit
[ ! -f "suite/Performance.hs" ] && echo "performance.sh: Wrong directory!" && exit

mkdir -p suite/performance/Results

# echo "Enter a description of this test set: "
# read DESC
DESC=$2
NAME=`date +%y%m%d-%H%M`

echo "performance.sh: Configuring..."
cabal configure --enable-benchmarks
echo "performance.sh: Building..."
cabal build

echo $NAME $HOSTNAME $DESC >> "suite/performance/Results/descs.txt"
DIR="suite/performance/Results/$NAME"
mkdir $DIR

echo "performance.sh: Running..."
for i in `seq 1 $1`
do
   echo
   echo
   echo
   echo "performance.sh: Benchmark -N$i:"
   cabal bench --benchmark-options="-s 20 -u $DIR/N$i.csv LSC2012 +RTS -N$i"
done

echo "performance.sh: Benchmarks complete."