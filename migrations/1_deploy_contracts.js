const Battleship = artifacts.require("Battleship.sol");
module.exports = function (instance) {
    instance.deploy(Battleship);
};
