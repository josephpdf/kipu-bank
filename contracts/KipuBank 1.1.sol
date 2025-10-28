// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title KipuBank
/// @author Joseph (EDP ETH Kipu)
/// @notice Banco simple para depositar ETH en bóvedas personales con límites y contador de operaciones.
/// @dev Implementa prácticas de seguridad: errores personalizados, checks-effects-interactions, reentrancy guard simple.

contract KipuBank {

    // ======================================================
    // VARIABLES INMUTABLES
    // ======================================================
    
    /// @notice Límite máximo total de ETH que puede contener el contrato (establecido en deploy).
    uint256 public immutable bankCap;

    /// @notice Límite máximo de retiro por transacción.
    uint256 public immutable perTxWithdrawLimit;

    /// @notice Dirección del dueño del contrato.
    address public immutable owner;

    // ======================================================
    // VARIABLES DE ALMACENAMIENTO
    // ======================================================

    /// @notice Total de ETH depositado en el contrato.
    uint256 public totalDeposited;

    /// @notice Total de ETH retirado del contrato.
    uint256 public totalWithdrawn;

    /// @notice Número total de depósitos realizados.
    uint256 public depositCount;

    /// @notice Número total de retiros realizados.
    uint256 public withdrawCount;

    /// @notice Saldo individual de cada usuario.
    mapping(address => uint256) private vault;

    /// @notice Historial de depósitos de cada usuario.
    mapping(address => uint256[]) private depositHistory;

    /// @notice Historial de retiros de cada usuario.
    mapping(address => uint256[]) private withdrawHistory;

    // ======================================================
    // SEGURIDAD - REENTRANCY GUARD
    // ======================================================

    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    // ======================================================
    // EVENTOS
    // ======================================================

    /// @notice Evento emitido cuando un usuario realiza un depósito exitoso.
    event Deposit(address indexed user, uint256 amount);

    /// @notice Evento emitido cuando un usuario realiza un retiro exitoso.
    event Withdraw(address indexed user, uint256 amount);

    // ======================================================
    // ERRORES PERSONALIZADOS
    // ======================================================

    /// @notice Se lanza cuando quien llama no es el dueño.
    error NotOwner();

    /// @notice Se lanza cuando se intenta depositar 0 ETH.
    error ZeroDeposit();

    /// @notice Se lanza cuando el depósito supera el límite global del banco.
    error BankCapExceeded(uint256 attempted, uint256 cap);

    /// @notice Se lanza cuando el saldo disponible es insuficiente para retirar.
    error InsufficientBalance(uint256 available, uint256 requested);

    /// @notice Se lanza cuando el retiro excede el límite por transacción.
    error WithdrawLimitExceeded(uint256 attempted, uint256 limit);

    // ======================================================
    // CONSTRUCTOR
    // ======================================================

    /// @notice Inicializa el contrato con límites de banco y retiro, y define el dueño.
    /// @param _bankCap Límite global de depósitos.
    /// @param _perTxWithdrawLimit Límite máximo de retiro por transacción.
    constructor(uint256 _bankCap, uint256 _perTxWithdrawLimit) {
        require(_bankCap > 0, "KipuBank: bankCap mayor que 0");
        require(_perTxWithdrawLimit > 0, "KipuBank: perTxWithdrawLimit mayor que 0");
        require(_perTxWithdrawLimit < _bankCap, "KipuBank: perTxWithdrawLimit < bankCap");

        bankCap = _bankCap;
        perTxWithdrawLimit = _perTxWithdrawLimit;
        owner = msg.sender;
        _status = _NOT_ENTERED;
    }

    // ======================================================
    // MODIFICADOR - REENTRANCY GUARD
    // ======================================================

    /// @notice Evita ataques de reentrancy.
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ======================================================
    // FUNCIONES EXTERNAS
    // ======================================================

    /// @notice Permite a un usuario depositar ETH en su bóveda personal.
    /// @dev Lanza error ZeroDeposit si msg.value == 0, BankCapExceeded si supera bankCap.
    function deposit() external payable {
        uint256 amount = msg.value;
        if (amount == 0) revert ZeroDeposit();
        if (address(this).balance > bankCap) revert BankCapExceeded(address(this).balance, bankCap);

        vault[msg.sender] += amount;
        totalDeposited += amount;
        depositCount += 1;
        depositHistory[msg.sender].push(amount);

        emit Deposit(msg.sender, amount);
    }

    /// @notice Permite retirar ETH hasta el límite por transacción.
    /// @param amount Cantidad a retirar.
    /// @dev Aplica patrón checks-effects-interactions y reentrancy guard.
    function withdraw(uint256 amount) external nonReentrant {
        uint256 balance = vault[msg.sender];
        if (balance < amount) revert InsufficientBalance(balance, amount);
        if (amount > perTxWithdrawLimit) revert WithdrawLimitExceeded(amount, perTxWithdrawLimit);

        vault[msg.sender] -= amount;
        totalWithdrawn += amount;
        withdrawCount += 1;
        withdrawHistory[msg.sender].push(amount);

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "KipuBank: Transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    // ======================================================
    // FUNCIONES VIEW
    // ======================================================

    /// @notice Devuelve estadísticas globales del banco.
    /// @return totalDeposits Número total de depósitos.
    /// @return totalWithdrawals Número total de retiros.
    /// @return contractBalance Saldo total en el contrato.
    function getBankStats() external view returns (
        uint256 totalDeposits,
        uint256 totalWithdrawals,
        uint256 contractBalance
    ) {
        totalDeposits = depositCount;
        totalWithdrawals = withdrawCount;
        contractBalance = address(this).balance;
    }

    /// @notice Devuelve el saldo de un usuario.
    /// @param user Dirección del usuario.
    /// @return balance Saldo disponible.
    function getUserBalance(address user) external view returns (uint256 balance) {
        balance = vault[user];
    }

    /// @notice Devuelve historial de depósitos de un usuario.
    /// @param user Dirección del usuario.
    /// @return history Array de depósitos realizados.
    function getDepositHistory(address user) external view returns (uint256[] memory history) {
        history = depositHistory[user];
    }

    /// @notice Devuelve historial de retiros de un usuario.
    /// @param user Dirección del usuario.
    /// @return history Array de retiros realizados.
    function getWithdrawHistory(address user) external view returns (uint256[] memory history) {
        history = withdrawHistory[user];
    }

    // ======================================================
    // FUNCIONES PRIVADAS
    // ======================================================

    /// @notice Lógica interna para obtener todos los movimientos de un usuario.
    /// @param user Dirección del usuario.
    /// @return deposits Historial de depósitos.
    /// @return withdrawals Historial de retiros.
    function _getAllUserMovements(address user) private view returns (
        uint256[] memory deposits,
        uint256[] memory withdrawals
    ) {
        deposits = depositHistory[user];
        withdrawals = withdrawHistory[user];
    }

    // ======================================================
    // FUNCIONES EXTERNAS SOLO PARA EL DUEÑO
    // ======================================================

    /// @notice Permite al dueño del contrato ver todos los movimientos de un usuario.
    /// @param user Dirección del usuario.
    /// @return deposits Historial de depósitos.
    /// @return withdrawals Historial de retiros.
    function getUserMovements(address user) external view returns (
        uint256[] memory deposits,
        uint256[] memory withdrawals
    ) {
        if (msg.sender != owner) revert NotOwner();
        return _getAllUserMovements(user);
    }

    function getBankBalance() public view returns (uint256) {
        return address(this).balance;
    }
}