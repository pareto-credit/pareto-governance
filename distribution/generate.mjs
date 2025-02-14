import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

// (1)
// read csv from file, which is in the format of address,amount
const values = fs.readFileSync("./distribution/distribution.csv", "utf8").split("\n").map(line => line.split(","));
// remove the last element if it is an empty string
if (values[values.length - 1].length === 0) values.pop();
// remove \r from numbers
values.forEach(value => value[1] = value[1].replace("\r", ""));
// log the number of values
console.log('Number of values:', values.length);

// print first 10 values 
console.log('First value:', values[0]);

// (2) Validate values before creating the tree
const validValues = values.filter(value => value[0] && !isNaN(value[1]));
const tree = StandardMerkleTree.of(validValues, ["address", "uint256"]);

// (3) Log the number of valid values before displaying the Merkle Root
console.log('Number of valid values:', validValues.length);
console.log('Merkle Root:', tree.root);

try {
  fs.writeFileSync("./distribution/tree.json", JSON.stringify(tree.dump(), null, 2));
  console.log("Merkle Tree has been written to tree.json successfully.");
} catch (error) {
  console.error("Error writing to tree.json:", error);
}

// (4) Find the proof for the first address as a test
for (const [i, v] of tree.entries()) {
  if (v[0] === '0x3675d2a334f17bcd4689533b7af263d48d96ec72') {
    const proof = tree.getProof(i);
    console.log('Value:', v);
    console.log('Proof:', proof);

    const isValidProof = StandardMerkleTree.verify(tree.root, ['address', 'uint256'], v, proof)
    console.log('Is Valid Proof:', isValidProof);
    break;
  }
}