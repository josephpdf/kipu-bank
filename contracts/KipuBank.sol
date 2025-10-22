// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title KipuBank
/// @author Joseph (EDP ETH Kipu)
/// @notice Banco simple para depositar ETH en bóvedas personales con límites y contador de operaciones.
/// @dev Implementa prácticas de seguridad: errores personalizados, checks-effects-interactions, reentrancy guard simple.
contract KipuBank {
    /*//////////////////////////////////////////////////////////////
                                ERRORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Se lanza cuando el depósito excede el límite global del banco.
    error BankCapExceeded(uint256 attempted, uint256 remainingCap);

    /// @notice Se lanza cuando el usuario intenta retirar más de su saldo.
    error InsufficientBalance(address account, uint256 requested, uint256 available);

    /// @notice Se lanza cuando la solicitud de retiro supera el límite por transacción.
    error WithdrawLimitExceeded(uint256 requested, uint256 limit);

    /// @notice Se lanza cuando la transferencia nativa falla.
    error TransferFailed(address to, uint256 amount);

    /// @notice Se lanza cuando la cantidad enviada debe ser mayor que cero.
    error ZeroAmount();

    /// @notice Se lanza cuando la llamada se realiza en estado de reentrancy.
    error ReentrancyProtected();

    /*//////////////////////////////////////////////////////////////
                             VARIABLES INMUTABLES/CONSTANTES
    //////////////////////////////////////////////////////////////*/

    /// @notice Límite máximo total de ETH que puede contener el contrato (establecido en deploy).
    uint256 public immutable bankCap;

    /// @notice Límite máximo por retiro en una sola transacción.
    uint256 public immutable withdrawLimit;

    /*//////////////////////////////////////////////////////////////
                             VARIABLES DE ALMACENAMIENTO
    //////////////////////////////////////////////////////////////*/

    /// @notice Balance por usuario (en wei).
    mapping(address => uint256) private balances;

    /// @notice Número de depósitos totales del banco.
    uint256 public totalDepositCount;

    /// @notice Número de retiros totales del banco.
    uint256 public totalWithdrawCount;

    /// @notice Número de depósitos por usuario.
    mapping(address => uint256) public depositCountPerUser;

    /// @notice Número de retiros por usuario.
    mapping(address => uint256) public withdrawCountPerUser;

    /// @notice Total de ETH depositado en el contrato (suma de todos los depósitos).
    uint256 public totalDeposited;

    /*//////////////////////////////////////////////////////////////
                                 EVENTOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Evento emitido en cada depósito exitoso.
    event Deposit(address indexed account, uint256 amount, uint256 newBalance);

    /// @notice Evento emitido en cada retiro exitoso.
    event Withdraw(address indexed account, uint256 amount, uint256 newBalance);

    /*//////////////////////////////////////////////////////////////
                             PROTECCIÓN REENTRANCIA
    //////////////////////////////////////////////////////////////*/

    // 0 = no-entered, 1 = entered
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _bankCap Límite global del banco (en wei).
    /// @param _withdrawLimit Límite por retiro por transacción (en wei).
    constructor(uint256 _bankCap, uint256 _withdrawLimit) {
        require(_bankCap > 0, "bankCap > 0");
        require(_withdrawLimit > 0, "withdrawLimit > 0");
        bankCap = _bankCap;
        withdrawLimit = _withdrawLimit;
        _status = _NOT_ENTERED;
    }

    /*//////////////////////////////////////////////////////////////
                                 MODIFICADORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Previene reentrancy simple.
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyProtected();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /// @notice Valida que la cantidad sea mayor a cero.
    modifier amountNonZero(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            FUNCIONES EXTERNAS / PUBLICAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Permite depositar ETH en la bóveda del remitente.
    /// @dev Función `external payable`, valida cap global y actualiza contadores.
    function deposit() external payable amountNonZero(msg.value) {
        uint256 newTotal = totalDeposited + msg.value;
        if (newTotal > bankCap) revert BankCapExceeded(msg.value, bankCap - totalDeposited);

        // efectos
        balances[msg.sender] += msg.value;
        totalDeposited = newTotal;

        // contadores
        totalDepositCount += 1;
        depositCountPerUser[msg.sender] += 1;

        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }

    /// @notice Retira ETH de la bóveda del remitente (máx `withdrawLimit` por tx).
    /// @param amount Cantidad a retirar en wei.
    /// @dev Sigue checks-effects-interactions y usa nonReentrant.
    function withdraw(uint256 amount) external nonReentrant amountNonZero(amount) {
        if (amount > withdrawLimit) revert WithdrawLimitExceeded(amount, withdrawLimit);

        uint256 bal = balances[msg.sender];
        if (amount > bal) revert InsufficientBalance(msg.sender, amount, bal);

        // checks done -> effects
        balances[msg.sender] = bal - amount;
        totalWithdrawCount += 1;
        withdrawCountPerUser[msg.sender] += 1;

        // interactions (transfer seguro via call)
        _safeSend(payable(msg.sender), amount);

        emit Withdraw(msg.sender, amount, balances[msg.sender]);
    }

    /*//////////////////////////////////////////////////////////////
                            FUNCIONES VIEW / PURE
    //////////////////////////////////////////////////////////////*/

    /// @notice Retorna el balance del usuario en wei.
    /// @param account Dirección a consultar.
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @notice Retorna cuánto queda disponible del bankCap (en wei).
    function remainingBankCap() external view returns (uint256) {
        return bankCap - totalDeposited;
    }

    /*//////////////////////////////////////////////////////////////
                            FUNCIONES PRIVADAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Envía ETH de forma segura usando call y revert personalizado si falla.
    /// @param to Dirección destino (payable).
    /// @param amount Cantidad a enviar en wei.
    function _safeSend(address payable to, uint256 amount) private {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert TransferFailed(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            FUNCIONES DE RECIBE / FALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Recibe ETH y lo trata como depósito (con el remitente = msg.sender).
    receive() external payable {
        // delega a deposit() para aplicar reglas y eventos
        // NOTA: no podemos usar `deposit{value: msg.value}()` por external call cost/limit
        // Por simplicidad y transparencia, repetimos la lógica mínima:
        uint256 newTotal = totalDeposited + msg.value;
        if (newTotal > bankCap) revert BankCapExceeded(msg.value, bankCap - totalDeposited);

        balances[msg.sender] += msg.value;
        totalDeposited = newTotal;
        totalDepositCount += 1;
        depositCountPerUser[msg.sender] += 1;
        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }

    fallback() external payable {
        // acepta fondos pero los trata como depósito (misma lógica que receive)
        uint256 newTotal = totalDeposited + msg.value;
        if (newTotal > bankCap) revert BankCapExceeded(msg.value, bankCap - totalDeposited);

        balances[msg.sender] += msg.value;
        totalDeposited = newTotal;
        totalDepositCount += 1;
        depositCountPerUser[msg.sender] += 1;
        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }
}
