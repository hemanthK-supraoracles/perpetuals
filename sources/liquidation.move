module perpetual_trading::lp_perpetual {
    use std::signer;
    use std::error;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_hash;
    use aptos_framework::account;
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_framework::event::{Self, EventHandle};

    /// Error codes
    const E_NOT_INITIALIZED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_POSITION_NOT_FOUND: u64 = 4;
    const E_INVALID_LEVERAGE: u64 = 5;
    const E_OPEN_INTEREST_EXCEEDED: u64 = 6;
    const E_INVALID_TAKE_PROFIT_PRICE: u64 = 7;
    const E_POSITION_ALREADY_EXISTS: u64 = 8;
    const E_ORACLE_PRICE_STALE: u64 = 9;
    const E_INSUFFICIENT_LP_BALANCE: u64 = 10;
    const E_INVALID_ORDER_TYPE: u64 = 11;
    const E_NOT_ADMIN: u64 = 12;
    const E_USER_HAS_NO_LIQUIDITY: u64 = 13;
    const E_INVALID_LPTOKEN_BALANCE: u64 = 14;
    const E_INVALID_COLLATERAL_AMOUNT: u64 = 15;
    const E_INSUFFICIENT_LPTOKEN_BALANCE: u64 = 16;
    const E_USER_HAS_NO_POSITIONS: u64 = 17;
    const E_NOT_ENOUGH_LIQUIDITY: u64 = 18;

    /// Constants
    const DECIMALS: u64 = 100000000; // 8 decimals
    const OPENING_FEE_BPS: u64 = 50; // 0.5%
    const CLOSING_FEE_BPS: u64 = 50; // 0.5%
    const BPS_DIVISOR: u64 = 10000;
    const MAX_LEVERAGE: u64 = 100;
    const MAX_TAKE_PROFIT_BPS: u64 = 50000; // 500%
    const ORACLE_PRICE_VALIDITY: u64 = 60000; // 60 seconds in milliseconds

    /// Position and order types
    const ORDER_TYPE_MARKET: u8 = 0;
    const ORDER_TYPE_LIMIT: u8 = 1;
    const POSITION_STATUS_PENDING: u8 = 0;
    const POSITION_STATUS_ACTIVE: u8 = 1;
    const POSITION_STATUS_CLOSED: u8 = 2;

    /// LP Token structure
    struct LPToken<phantom CoinType> has key, store {
        value: u64
    }

    /// Liquidity Pool structure
    struct LiquidityPool<phantom CoinType> has key {
        /// Total USDC balance in the pool
        total_balance: u64,
        /// Total LP tokens minted
        total_lp_tokens: u64,
        /// USDC coin store
        coin_store: Coin<CoinType>,
        /// Total open interest (sum of all position sizes)
        total_open_interest: u64,
        /// LP providers table
        lp_providers: Table<address, u64>,
        /// Events
        add_liquidity_events: EventHandle<AddLiquidityEvent>,
        remove_liquidity_events: EventHandle<RemoveLiquidityEvent>
    }

    /// Position structure
    struct Position has key, store {
        /// Position ID (random alphanumeric string)
        id: String,
        /// Position owner
        owner: address,
        /// Asset type (e.g., "BTC", "ETH")
        asset_type: String,
        /// True for long, false for short
        is_long: bool,
        /// Leverage multiplier
        leverage: u64,
        /// Collateral amount in USDC
        collateral_amount: u64,
        /// Position size in USDC (collateral * leverage)
        position_size: u64,
        /// Order type (market/limit)
        order_type: u8,
        /// Entry price (for limit orders)
        entry_price: u64,
        /// Take profit price (optional)
        take_profit: u64,
        /// Stop loss price (optional)
        stop_loss: u64,
        /// Liquidation price
        liquidation_price: u64,
        /// Actual entry price (when position is activated)
        actual_entry_price: u64,
        /// Position status
        status: u8,
        /// Timestamp when position was created
        created_at: u64,
        /// Timestamp when position was activated
        activated_at: u64,
        /// Opening fees paid
        opening_fees: u64
    }

    /// User positions storage
    struct UserPositions has key {
        positions: Table<String, Position>,
        // next_position_id: u64,
        active_positions: vector<String>
    }

    /// Oracle price structure
    struct OraclePrice has key {
        asset_prices: Table<String, AssetPrice>,
        oracle_admin: address
    }

    /// Asset price structure
    struct AssetPrice has drop, store {
        price: u64,
        timestamp: u64
    }

    /// Global state
    struct GlobalState has key {
        admin: address,
        is_initialized: bool,
        total_positions: u64,
        position_events: EventHandle<PositionEvent>,
        trade_events: EventHandle<TradeEvent>
    }

    /// Events
    #[event]
    struct AddLiquidityEvent has drop, store {
        user: address,
        usdc_amount: u64,
        lp_tokens_minted: u64,
        timestamp: u64
    }

    #[event]
    struct RemoveLiquidityEvent has drop, store {
        user: address,
        lp_tokens_burned: u64,
        usdc_amount: u64,
        timestamp: u64
    }

    #[event]
    struct PositionEvent has drop, store {
        position_id: String,
        user: address,
        asset_type: String,
        is_long: bool,
        position_size: u64,
        entry_price: u64,
        event_type: String,
        timestamp: u64
    }

    #[event]
    struct TradeEvent has drop, store {
        position_id: String,
        user: address,
        pnl: u64,
        is_profit: bool,
        closing_fees: u64,
        timestamp: u64
    }

    /// Initialize the contract
    public entry fun initialize<CoinType>(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        assert!(
            @aptos_perpetuals == signer::address_of(admin),
            error::permission_denied(E_NOT_ADMIN)
        );

        // Initialize global state
        move_to(
            admin,
            GlobalState {
                admin: admin_addr,
                is_initialized: true,
                total_positions: 0,
                position_events: account::new_event_handle<PositionEvent>(admin),
                trade_events: account::new_event_handle<TradeEvent>(admin)
            }
        );

        // Initialize liquidity pool
        move_to(
            admin,
            LiquidityPool<CoinType> {
                total_balance: 0,
                total_lp_tokens: 0,
                coin_store: coin::zero<CoinType>(),
                total_open_interest: 0,
                lp_providers: table::new(),
                add_liquidity_events: account::new_event_handle<AddLiquidityEvent>(admin),
                remove_liquidity_events: account::new_event_handle<RemoveLiquidityEvent>(
                    admin
                )
            }
        );

        // Initialize oracle
        move_to(
            admin,
            OraclePrice { asset_prices: table::new(), oracle_admin: admin_addr }
        );
    }

    /// Add liquidity to the pool
    public entry fun add_liquidity<CoinType>(
        user: &signer, amount: u64, pool_address: address
    ) acquires LiquidityPool {
        assert!(amount > 0, error::invalid_argument(E_INVALID_AMOUNT));

        let user_addr = signer::address_of(user);
        let pool = borrow_global_mut<LiquidityPool<CoinType>>(pool_address);

        // Calculate LP tokens to mint
        let lp_tokens_to_mint =
            if (pool.total_lp_tokens == 0) {
                // Initial liquidity - 1:1 ratio
                amount
            } else {
                // Calculate based on current pool ratio
                (amount * pool.total_lp_tokens) / pool.total_balance
            };

        // Transfer USDC from user to pool
        let coins = coin::withdraw<CoinType>(user, amount);
        coin::merge(&mut pool.coin_store, coins);

        // Update pool state
        pool.total_balance = pool.total_balance + amount;
        pool.total_lp_tokens = pool.total_lp_tokens + lp_tokens_to_mint;

        // Update user's LP token balance
        if (table::contains(&pool.lp_providers, user_addr)) {
            let current_balance = table::borrow_mut(&mut pool.lp_providers, user_addr);
            *current_balance = *current_balance + lp_tokens_to_mint;
        } else {
            table::add(&mut pool.lp_providers, user_addr, lp_tokens_to_mint);
        };

        // Emit event
        event::emit_event(
            &mut pool.add_liquidity_events,
            AddLiquidityEvent {
                user: user_addr,
                usdc_amount: amount,
                lp_tokens_minted: lp_tokens_to_mint,
                timestamp: timestamp::now_microseconds()
            }
        );
    }

    /// Remove liquidity from the pool
    public entry fun remove_liquidity<CoinType>(
        user: &signer, lp_tokens_to_burn: u64, pool_address: address
    ) acquires LiquidityPool {
        let user_addr = signer::address_of(user);
        let pool = borrow_global_mut<LiquidityPool<CoinType>>(pool_address);

        // Check user has enough LP tokens
        assert!(
            table::contains(&pool.lp_providers, user_addr),
            error::not_found(E_USER_HAS_NO_LIQUIDITY)
        );
        let user_lp_balance = table::borrow_mut(&mut pool.lp_providers, user_addr);
        assert!(
            *user_lp_balance >= lp_tokens_to_burn,
            error::invalid_argument(E_INSUFFICIENT_LPTOKEN_BALANCE)
        );

        // Calculate USDC to return
        let usdc_to_return = (lp_tokens_to_burn * pool.total_balance)
            / pool.total_lp_tokens;

        // Check pool has enough balance
        assert!(
            pool.total_balance >= usdc_to_return,
            error::invalid_argument(E_INSUFFICIENT_LP_BALANCE)
        );

        // Update user's LP token balance
        *user_lp_balance = *user_lp_balance - lp_tokens_to_burn;

        // Update pool state
        pool.total_balance = pool.total_balance - usdc_to_return;
        pool.total_lp_tokens = pool.total_lp_tokens - lp_tokens_to_burn;

        // Transfer USDC to user
        let coins = coin::extract(&mut pool.coin_store, usdc_to_return);
        coin::deposit(user_addr, coins);

        // Emit event
        event::emit_event(
            &mut pool.remove_liquidity_events,
            RemoveLiquidityEvent {
                user: user_addr,
                lp_tokens_burned: lp_tokens_to_burn,
                usdc_amount: usdc_to_return,
                timestamp: timestamp::now_microseconds()
            }
        );
    }

    /// Create a new position
    public entry fun create_position<CoinType>(
        user: &signer,
        asset_type: String,
        is_long: bool,
        leverage: u64,
        collateral_amount: u64,
        order_type: u8,
        entry_price: u64, // For limit orders
        take_profit: u64, // 0 if not set
        stop_loss: u64, // 0 if not set
        pool_address: address,
        global_address: address
    ) acquires UserPositions, GlobalState, LiquidityPool {
        let user_addr = signer::address_of(user);

        // Validate inputs
        assert!(
            leverage >= 1 && leverage <= MAX_LEVERAGE,
            error::invalid_argument(E_INVALID_LEVERAGE)
        );
        assert!(
            collateral_amount > 0, error::invalid_argument(E_INVALID_COLLATERAL_AMOUNT)
        );
        assert!(
            order_type == ORDER_TYPE_MARKET || order_type == ORDER_TYPE_LIMIT,
            error::invalid_argument(E_INVALID_ORDER_TYPE)
        );

        if (take_profit > 0) {
            let max_tp_size = collateral_amount * MAX_TAKE_PROFIT_BPS / BPS_DIVISOR;
            assert!(
                take_profit <= max_tp_size,
                error::invalid_argument(E_INVALID_TAKE_PROFIT_PRICE)
            );
        };

        let position_size = collateral_amount * leverage;

        // Check open interest limit
        let pool = borrow_global<LiquidityPool<CoinType>>(pool_address);
        assert!(
            pool.total_open_interest + position_size <= pool.total_balance,
            error::invalid_argument(E_OPEN_INTEREST_EXCEEDED)
        );

        // Calculate fees
        let opening_fees = (position_size * OPENING_FEE_BPS) / BPS_DIVISOR;
        let total_required = collateral_amount + opening_fees;

        // Transfer collateral and fees from user
        let coins = coin::withdraw<CoinType>(user, total_required);
        let pool_mut = borrow_global_mut<LiquidityPool<CoinType>>(pool_address);
        coin::merge(&mut pool_mut.coin_store, coins);

        // Calculate liquidation price
        let liquidation_price =
            calculate_liquidation_price(
                is_long,
                entry_price,
                collateral_amount,
                position_size,
                opening_fees
            );

        // Initialize user positions if not exists
        if (!exists<UserPositions>(user_addr)) {
            move_to(
                user,
                UserPositions {
                    positions: table::new(),
                    active_positions: vector::empty()
                }
            );
        };

        let user_positions = borrow_global_mut<UserPositions>(user_addr);
        let current_time = timestamp::now_microseconds();

        let position_id = generate_position_id(user_addr, current_time);

        // Create position
        let position = Position {
            id: position_id,
            owner: user_addr,
            asset_type: asset_type,
            is_long,
            leverage,
            collateral_amount,
            position_size,
            order_type,
            entry_price,
            take_profit,
            stop_loss,
            liquidation_price,
            actual_entry_price: 0,
            status: POSITION_STATUS_PENDING,
            created_at: timestamp::now_microseconds(),
            activated_at: 0,
            opening_fees
        };

        // Store position
        table::add(&mut user_positions.positions, position_id, position);

        // Update global state
        let global_state = borrow_global_mut<GlobalState>(global_address);
        global_state.total_positions = global_state.total_positions + 1;

        // For market orders, activate immediately
        if (order_type == ORDER_TYPE_MARKET) {
            activate_position<CoinType>(
                user_addr,
                position_id,
                entry_price,
                pool_address,
                global_address
            );
        };
    }

    /// Activate a pending position
    fun activate_position<CoinType>(
        user_addr: address,
        position_id: String,
        current_price: u64,
        pool_address: address,
        global_address: address
    ) acquires UserPositions, GlobalState, LiquidityPool {
        let user_positions = borrow_global_mut<UserPositions>(user_addr);
        let position = table::borrow_mut(&mut user_positions.positions, position_id);

        // Update position
        position.actual_entry_price = current_price;
        position.status = POSITION_STATUS_ACTIVE;
        position.activated_at = timestamp::now_microseconds();

        // Add to active positions
        vector::push_back(&mut user_positions.active_positions, position_id);

        // Update pool open interest
        let pool = borrow_global_mut<LiquidityPool<CoinType>>(pool_address);
        pool.total_open_interest = pool.total_open_interest + position.position_size;

        // Emit event
        let global_state = borrow_global_mut<GlobalState>(global_address);
        event::emit_event(
            &mut global_state.position_events,
            PositionEvent {
                position_id,
                user: user_addr,
                asset_type: position.asset_type,
                is_long: position.is_long,
                position_size: position.position_size,
                entry_price: current_price,
                event_type: string::utf8(b"position_opened"),
                timestamp: timestamp::now_microseconds()
            }
        );
    }

    /// Close a position
    public entry fun close_position<CoinType>(
        user: &signer,
        position_id: String,
        current_price: u64,
        pool_address: address,
        global_address: address
    ) acquires UserPositions, GlobalState, LiquidityPool {
        let user_addr = signer::address_of(user);
        let user_positions = borrow_global_mut<UserPositions>(user_addr);

        assert!(
            table::contains(&user_positions.positions, position_id),
            error::not_found(E_POSITION_NOT_FOUND)
        );
        let position = table::borrow_mut(&mut user_positions.positions, position_id);

        // Calculate P&L
        let (pnl, is_profit) =
            calculate_pnl(
                position.is_long,
                position.actual_entry_price,
                current_price,
                position.position_size
            );

        // Calculate closing fees
        let closing_fees = (position.position_size * CLOSING_FEE_BPS) / BPS_DIVISOR;

        let pool = borrow_global_mut<LiquidityPool<CoinType>>(pool_address);

        // Update LP balance based on trader P&L
        if (is_profit) {
            // Trader profits, LP loses
            let total_payout = position.collateral_amount + pnl;
            let net_payout =
                if (total_payout > closing_fees) {
                    total_payout - closing_fees
                } else { 0 };

            // Debit LP balance
            pool.total_balance = pool.total_balance - pnl;

            // Pay trader
            if (net_payout > 0) {
                let coins = coin::extract(&mut pool.coin_store, net_payout);
                coin::deposit(user_addr, coins);
            };
        } else {
            // Trader loses, LP gains
            let remaining_collateral =
                if (position.collateral_amount > pnl) {
                    position.collateral_amount - pnl
                } else { 0 };

            let net_payout =
                if (remaining_collateral > closing_fees) {
                    remaining_collateral - closing_fees
                } else { 0 };

            // Credit LP balance
            pool.total_balance = pool.total_balance + pnl;

            // Pay remaining to trader
            if (net_payout > 0) {
                let coins = coin::extract(&mut pool.coin_store, net_payout);
                coin::deposit(user_addr, coins);
            };
        };

        // Update position status
        position.status = POSITION_STATUS_CLOSED;

        // Remove from active positions
        let (found, index) = vector::index_of(
            &user_positions.active_positions, &position_id
        );
        if (found) {
            vector::remove(&mut user_positions.active_positions, index);
        };

        // Update pool open interest
        pool.total_open_interest = pool.total_open_interest - position.position_size;

        // Emit events
        let global_state = borrow_global_mut<GlobalState>(global_address);
        event::emit_event(
            &mut global_state.trade_events,
            TradeEvent {
                position_id,
                user: user_addr,
                pnl,
                is_profit,
                closing_fees,
                timestamp: timestamp::now_microseconds()
            }
        );

        event::emit_event(
            &mut global_state.position_events,
            PositionEvent {
                position_id,
                user: user_addr,
                asset_type: position.asset_type,
                is_long: position.is_long,
                position_size: position.position_size,
                entry_price: current_price,
                event_type: string::utf8(b"position_closed"),
                timestamp: timestamp::now_microseconds()
            }
        );
    }

    /// Generate random alphanumeric position ID
    fun generate_position_id(user_addr: address, timestamp: u64): String {
        let seed = vector::empty<u8>();

        // Add user address bytes
        let addr_bytes = std::bcs::to_bytes(&user_addr);
        vector::append(&mut seed, addr_bytes);

        // Add timestamp bytes
        let time_bytes = std::bcs::to_bytes(&timestamp);
        vector::append(&mut seed, time_bytes);

        // Add some entropy from current microseconds
        let micro_time = timestamp::now_microseconds();
        let micro_bytes = std::bcs::to_bytes(&micro_time);
        vector::append(&mut seed, micro_bytes);

        // Hash the seed
        let hash = aptos_hash::sha3_512(seed);

        // Convert to alphanumeric string (first 18 bytes for 18-character ID)
        let chars = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        let result = vector::empty<u8>();

        let i = 0;
        while (i < 18) {
            let byte_val = *vector::borrow(&hash, i);
            let char_index = (byte_val as u64) % 36;
            vector::push_back(&mut result, *vector::borrow(&chars, char_index));
            i = i + 1;
        };

        string::utf8(result)
    }

    /// Calculate P&L for a position
    fun calculate_pnl(
        is_long: bool,
        entry_price: u64,
        current_price: u64,
        position_size: u64
    ): (u64, bool) {
        let price_diff =
            if (current_price > entry_price) {
                current_price - entry_price
            } else {
                entry_price - current_price
            };

        let pnl = (position_size * price_diff) / entry_price;

        let is_profit =
            if (is_long) {
                current_price > entry_price
            } else {
                current_price < entry_price
            };

        (pnl, is_profit)
    }

    /// Calculate liquidation price
    fun calculate_liquidation_price(
        is_long: bool,
        entry_price: u64,
        collateral_amount: u64,
        position_size: u64,
        fees: u64
    ): u64 {
        let max_loss = collateral_amount - fees;
        let liquidation_threshold = (max_loss * entry_price) / position_size;

        if (is_long) {
            entry_price - liquidation_threshold
        } else {
            entry_price + liquidation_threshold
        }
    }

    /// Update oracle price (admin only)
    public entry fun update_oracle_price(
        admin: &signer,
        asset_type: String,
        price: u64,
        oracle_address: address
    ) acquires OraclePrice {
        let oracle = borrow_global_mut<OraclePrice>(oracle_address);
        assert!(
            signer::address_of(admin) == oracle.oracle_admin,
            error::permission_denied(E_NOT_INITIALIZED)
        );

        let asset_price = AssetPrice { price, timestamp: timestamp::now_microseconds() };

        if (table::contains(&oracle.asset_prices, asset_type)) {
            let existing_price = table::borrow_mut(&mut oracle.asset_prices, asset_type);
            *existing_price = asset_price;
        } else {
            table::add(&mut oracle.asset_prices, asset_type, asset_price);
        };
    }

    /// Get current LP token price
    #[view]
    public fun get_lp_token_price<CoinType>(pool_address: address): u64 acquires LiquidityPool {
        let pool = borrow_global<LiquidityPool<CoinType>>(pool_address);
        if (pool.total_lp_tokens == 0) {
            DECIMALS // 1.0 in decimal representation
        } else {
            (pool.total_balance * DECIMALS) / pool.total_lp_tokens
        }
    }

    /// Get user's LP token balance
    #[view]
    public fun get_user_lp_balance<CoinType>(
        user_addr: address, pool_address: address
    ): u64 acquires LiquidityPool {
        let pool = borrow_global<LiquidityPool<CoinType>>(pool_address);
        if (table::contains(&pool.lp_providers, user_addr)) {
            *table::borrow(&pool.lp_providers, user_addr)
        } else { 0 }
    }

    /// Get position details
    #[view]
    public fun get_position(
        user_addr: address, position_id: String
    ): (String, String, bool, u64, u64, u64, u8) acquires UserPositions {
        let user_positions = borrow_global<UserPositions>(user_addr);
        let position = table::borrow(&user_positions.positions, position_id);

        (
            position.id,
            position.asset_type,
            position.is_long,
            position.leverage,
            position.collateral_amount,
            position.position_size,
            position.status
        )
    }

    /// Get pool stats
    #[view]
    public fun get_pool_stats<CoinType>(pool_address: address): (u64, u64, u64) acquires LiquidityPool {
        let pool = borrow_global<LiquidityPool<CoinType>>(pool_address);
        (pool.total_balance, pool.total_lp_tokens, pool.total_open_interest)
    }
}
