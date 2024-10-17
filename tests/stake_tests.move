#[test_only]
module defiralia_staking::stake_tests {
    use std::option;

    use aptos_framework::coin;
    use aptos_framework::genesis;
    use aptos_framework::timestamp;

    use defiralia_staking::stake::{Self, is_finished};
    use defiralia_staking::stake_config;
    use defiralia_staking::stake_test_helpers::{new_account, initialize_reward_coin, initialize_stake_coin, mint_default_coin, StakeCoin, RewardCoin, new_account_with_stake_coins};

    // week in seconds, lockup period
    const WEEK_IN_SECONDS: u64 = 604800;

    const START_TIME: u64 = 682981200;

    public fun initialize_test(): (signer, signer) {
        genesis::setup();

        timestamp::update_global_time_for_test_secs(START_TIME);

        let defiralia_staking = new_account(@defiralia_staking);

        // create coins for pool to be valid
        initialize_reward_coin(&defiralia_staking, 6);
        initialize_stake_coin(&defiralia_staking, 6);

        let emergency_admin = new_account(@stake_emergency_admin);
        stake_config::initialize(&emergency_admin, @treasury);
        (defiralia_staking, emergency_admin)
    }

    #[test]
    public fun test_register() {
        initialize_test();

        let alice_acc = new_account(@alice);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&alice_acc, reward_coins, duration, option::none());

        // check pool statistics
        let (reward_per_sec, accum_reward, last_updated, reward_amount, scale) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@alice);
        let end_ts = stake::get_end_timestamp<StakeCoin, RewardCoin>(@alice);
        assert!(end_ts == START_TIME + duration, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);
        assert!(reward_amount == 15768000000000, 1);
        assert!(scale == 1000000000000, 1);
        assert!(stake::pool_exists<StakeCoin, RewardCoin>(@alice), 1);
        assert!(stake::get_pool_total_stake<StakeCoin, RewardCoin>(@alice) == 0, 1);
    }

    #[test]
    public fun test_register_two_pools() {
        initialize_test();

        let alice_acc = new_account(@alice);
        let bob_acc = new_account(@bob);

        // register staking pool 1 with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&alice_acc, reward_coins, duration, option::none());

        // register staking pool 2 with rewards
        let reward_coins = mint_default_coin<StakeCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<RewardCoin, StakeCoin>(&bob_acc, reward_coins, duration, option::none());

        // check pools exist
        assert!(stake::pool_exists<StakeCoin, RewardCoin>(@alice), 1);
        assert!(stake::pool_exists<RewardCoin,StakeCoin>(@bob), 1);
    }

    #[test]
    public fun test_deposit_reward_coins() {
        let (defiralia_staking, _) = initialize_test();
        let alice_acc = new_account(@alice);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // check pool statistics
        let pool_finish_time = START_TIME + duration;
        let (reward_per_sec, _, _, reward_amount, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let end_ts = stake::get_end_timestamp<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(end_ts == pool_finish_time, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(reward_amount == 15768000000000, 1);

        // deposit more rewards
        let reward_coins = mint_default_coin<RewardCoin>(604800000000);
        stake::deposit_reward_coins<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, reward_coins);

        // check pool statistics
        let pool_finish_time = pool_finish_time + 604800;
        let (reward_per_sec, _, _, reward_amount, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let end_ts = stake::get_end_timestamp<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(end_ts == pool_finish_time, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(reward_amount == 16372800000000, 1);

        // wait to a second before pool duration end
        timestamp::update_global_time_for_test_secs(pool_finish_time - 1);

        // deposit more rewards
        let reward_coins = mint_default_coin<RewardCoin>(604800000000);
        stake::deposit_reward_coins<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, reward_coins);

        // check pool statistics
        let pool_finish_time = pool_finish_time + 604800;
        let (reward_per_sec, _, _, reward_amount, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let end_ts = stake::get_end_timestamp<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(end_ts == pool_finish_time, 1);
        assert!(reward_per_sec == 1000000, 1);
        assert!(reward_amount == 16977600000000, 1);
    }

    #[test]
    public fun test_stake_and_unstake() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 900000000);
        let bob_acc = new_account_with_stake_coins(@bob, 99000000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // check no stakes
        assert!(!stake::stake_exists<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);
        assert!(!stake::stake_exists<StakeCoin, RewardCoin>(@defiralia_staking, @bob), 1);

        // stake 500 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 500000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);
        assert!(coin::balance<StakeCoin>(@alice) == 400000000, 1);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 500000000, 1);
        assert!(stake::get_pool_total_stake<StakeCoin, RewardCoin>(@defiralia_staking) == 500000000, 1);

        // stake 99 StakeCoins from bob
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 99000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);
        assert!(coin::balance<StakeCoin>(@bob) == 0, 1);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 99000000, 1);
        assert!(stake::get_pool_total_stake<StakeCoin, RewardCoin>(@defiralia_staking) == 599000000, 1);

        // stake 300 StakeCoins more from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 300000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);
        assert!(coin::balance<StakeCoin>(@alice) == 100000000, 1);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 800000000, 1);
        assert!(stake::get_pool_total_stake<StakeCoin, RewardCoin>(@defiralia_staking) == 899000000, 1);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // unstake 400 StakeCoins from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 400000000);
        assert!(coin::value(&coins) == 400000000, 1);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 400000000, 1);
        assert!(stake::get_pool_total_stake<StakeCoin, RewardCoin>(@defiralia_staking) == 499000000, 1);
        coin::deposit<StakeCoin>(@alice, coins);

        // unstake all 99 StakeCoins from bob
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 99000000);
        assert!(coin::value(&coins) == 99000000, 1);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 0, 1);
        assert!(stake::get_pool_total_stake<StakeCoin, RewardCoin>(@defiralia_staking) == 400000000, 1);
        coin::deposit<StakeCoin>(@bob, coins);
    }

    #[test]
    public fun test_unstake_works_after_pool_duration_end() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 12345);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 12345);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait until pool expired and a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS);

        // unstake from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 12345);
        assert!(coin::value(&coins) == 12345, 1);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        assert!(stake::get_pool_total_stake<StakeCoin, RewardCoin>(@defiralia_staking) == 0, 1);
        coin::deposit<StakeCoin>(@alice, coins);
    }

    #[test]
    public fun test_stake_lockup_period() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 1000000);
        let bob_acc = new_account_with_stake_coins(@bob, 1000000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // check alice stake unlock time
        let unlock_time = stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS, 1);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 100);

        // stake from bob
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        // check bob stake unlock time
        let unlock_time = stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS + 100, 1);

        // stake more from alice before lockup period end
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // check alice stake unlock time updated
        let unlock_time = stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS + 100, 1);

        // wait one week
        timestamp::update_global_time_for_test_secs(START_TIME + 100 + WEEK_IN_SECONDS);

        // unstake from alice after lockup period end
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 1000000);
        coin::deposit(@alice, coins);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 200 + WEEK_IN_SECONDS);

        // partial unstake from bob after lockup period end
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 250000);
        coin::deposit(@bob, coins);

        // wait 100 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 300 + WEEK_IN_SECONDS);

        // stake more from bob after lockup period end
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        // check bob stake unlock time updated
        let unlock_time = stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        assert!(unlock_time == START_TIME + WEEK_IN_SECONDS + 300 + WEEK_IN_SECONDS, 1);

        // wait 1 year
        timestamp::update_global_time_for_test_secs(START_TIME + 31536000);

        // unstake from bob almost year after lockup period end
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 250000);
        coin::deposit(@bob, coins);
    }

    #[test]
    public fun test_get_start_timestamp() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 604805;
        let start_ts = timestamp::now_seconds();
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        assert!(stake::get_start_timestamp<StakeCoin, RewardCoin>(@defiralia_staking) == start_ts, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);
        assert!(stake::get_start_timestamp<StakeCoin, RewardCoin>(@defiralia_staking) == start_ts, 1);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_get_start_timestamp_fails_no_pool_exists() {
        let _ = stake::get_start_timestamp<StakeCoin, RewardCoin>(@defiralia_staking);
    }

    #[test]
    public fun test_is_unlocked() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 500000);
        let bob_acc = new_account_with_stake_coins(@bob, 500000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 604805;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        assert!(!stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);

        // wait almost a week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS - 1);

        assert!(!stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);

        // stake from bob
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        assert!(!stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @bob), 1);

        // wait a second
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        assert!(stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);
        assert!(!stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @bob), 1);

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        assert!(stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);
        assert!(stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @bob), 1);

        // wait a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS);

        assert!(stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);
        assert!(stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @bob), 1);
    }

    #[test]
    public fun test_is_unlocked_early() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 500000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 3600;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        assert!(!stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);

        // wait almost a hour
        timestamp::update_global_time_for_test_secs(START_TIME + 3600 - 1);
        assert!(!stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);

        // wait a hour
        timestamp::update_global_time_for_test_secs(START_TIME + 3600);
        assert!(stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice), 1);
    }

    #[test]
    public fun test_get_unlock_time_early() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 500000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(604805000000);
        let duration = 3600;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 500000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        assert!(stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == START_TIME + 3600, 1);
    }

    #[test]
    public fun test_reward_calculation() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 900000000);
        let bob_acc = new_account_with_stake_coins(@bob, 99000000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // check stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 0, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 10);

        // synthetic recalculate
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        // (reward_per_sec_rate * time passed / total_staked) + previous period
        assert!(accum_reward == 1000000000000, 1);
        assert!(last_updated == START_TIME + 10, 1);

        // check alice's stake
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 100000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 100000000, 1);

        // stake 50 StakeCoins from bob
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 50000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        // check bob's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        // stake amount * pool accum_reward
        // accumulated benefit that does not belong to bob
        assert!(unobtainable_reward == 50000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 0, 1);

        // stake 100 StakeCoins more from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 20);

        // synthetic recalculate
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @bob);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 1400000000000, 1);
        assert!(last_updated == START_TIME + 20, 1);

        // check alice's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 280000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 180000000, 1);

        // check bob's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        assert!(unobtainable_reward == 70000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 20000000, 1);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + 20 + WEEK_IN_SECONDS);

        // synthetic recalculate
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @bob);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 24193400000000000, 1);
        assert!(last_updated == START_TIME + 20 + WEEK_IN_SECONDS, 1);

        // check alice's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 4838680000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 4838580000000, 1);

        // check bob's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        assert!(unobtainable_reward == 1209670000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 1209620000000, 1);

        // unstake 100 StakeCoins from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit<StakeCoin>(@alice, coins);

        // check alice's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 2419340000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 4838580000000, 1);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 30 + WEEK_IN_SECONDS);

        // synthetic recalculate
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @bob);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 24194066666666666, 1);
        assert!(last_updated == START_TIME + 30 + WEEK_IN_SECONDS, 1);

        // check alice's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        let earned_reward1 = stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 2419406666666, 1);
        assert!(earned_reward1 == 4838646666666, 1);

        // check bob's stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        let earned_reward2 = stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        assert!(unobtainable_reward == 1209703333333, 1);
        assert!(earned_reward2 == 1209653333333, 1);

        // 0.000001 RewardCoin lost during calculations
        let total_rewards = (30 + WEEK_IN_SECONDS) * 10000000;
        let total_earned = earned_reward1 + earned_reward2;
        let losed_rewards = total_rewards - total_earned;

        assert!(losed_rewards == 1, 1);
    }

    #[test]
    public fun test_reward_calculation_works_well_when_pool_is_empty() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // wait one week with empty pool
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // check stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 0, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME + WEEK_IN_SECONDS, 1);

        // wait one week with stake
        timestamp::update_global_time_for_test_secs(START_TIME + (WEEK_IN_SECONDS * 2));

        // synthetic recalculate
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);

        // check stake parameters, here we count on that user receives reward for one week only
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        // 604800 seconds * 10 rew_per_second, all coins belong to user
        assert!(unobtainable_reward == 6048000000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 6048000000000, 1);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        // 604800 seconds * 10 rew_per_second / 100 total_staked
        assert!(accum_reward == 60480000000000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 2), 1);

        // unstake from alice
        let coins
            = stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit(@alice, coins);

        // check stake parameters
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        // 604800 seconds * 10 rew_per_second, all coins belong to user
        assert!(unobtainable_reward == 0, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 6048000000000, 1);

        // check pool parameters
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        // 604800 seconds * 10 rew_per_second / 100 total_staked
        assert!(accum_reward == 60480000000000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 2), 1);

        // wait few more weeks with empty pool
        timestamp::update_global_time_for_test_secs(START_TIME + (WEEK_IN_SECONDS * 5));

        // stake again from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // check stake parameters, user should not be able to claim rewards for period after unstake
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 6048000000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 6048000000000, 1);

        // check pool parameters, pool should not accumulate rewards when no stakes in it
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 60480000000000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 5), 1);

        // wait one week after stake
        timestamp::update_global_time_for_test_secs(START_TIME + (WEEK_IN_SECONDS * 6));

        // synthetic recalculate
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);

        // check stake parameters, user should not be able to claim rewards for period after unstake
        let unobtainable_reward =
            stake::get_unobtainable_reward<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(unobtainable_reward == 12096000000000, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 12096000000000, 1);

        // check pool parameters, pool should not accumulate rewards when no stakes in it
        let (_, accum_reward, last_updated, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 120960000000000000, 1);
        assert!(last_updated == START_TIME + (WEEK_IN_SECONDS * 6), 1);
    }

    #[test]
    public fun test_harvest() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);
        let bob_acc = new_account_with_stake_coins(@bob, 100000000);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 10);

        // harvest from alice
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);

        // check amounts
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        assert!(coin::value(&coins) == 100000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);

        // stake 100 StakeCoins from bob
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + 10 + WEEK_IN_SECONDS);

        // harvest from alice
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);

        // check amounts
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        assert!(coin::value(&coins) == 3024000000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);

        // harvest from bob
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking);

        // check amounts
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 0, 1);
        assert!(coin::value(&coins) == 3024000000000, 1);

        coin::deposit<RewardCoin>(@bob, coins);

        // unstake 100 StakeCoins from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit<StakeCoin>(@bob, coins);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 20 + WEEK_IN_SECONDS);

        // harvest from bob
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking);

        // check amounts
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 0, 1);
        assert!(coin::value(&coins) == 100000000, 1);

        coin::deposit<RewardCoin>(@bob, coins);
    }

    #[test]
    public fun test_harvest_works_after_pool_duration_end() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait until pool expired and a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS);

        // harvest from alice
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);

        // check amounts
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        assert!(coin::value(&coins) == 157680000000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);
    }

    #[test]
    public fun test_stake_and_harvest_for_pool_less_than_week_duration() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);
        let bob_acc = new_account_with_stake_coins(@bob, 30000000);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        let reward_coins = mint_default_coin<RewardCoin>(302400000000);
        let duration = 302400;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 30000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 1);

        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);

        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        assert!(coin::value(&coins) == 232615384615, 1);

        coin::deposit<RewardCoin>(@alice, coins);

        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking);

        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 0, 1);
        assert!(coin::value(&coins) == 69784615384, 1);

        coin::deposit<RewardCoin>(@bob, coins);

        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit<StakeCoin>(@alice, coins);

        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 30000000);
        coin::deposit<StakeCoin>(@bob, coins);

        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @bob) == 0, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
    }

    #[test]
    public fun test_stake_and_harvest_big_real_values() {
        // well, really i just want to test large numbers with 8 decimals, so this why we have billions.
        let (defiralia_staking, _) = initialize_test();

        // 900b of coins.
        let alice_acc = new_account_with_stake_coins(@alice, 900000000000000000);
        // 100b of coins.
        let bob_acc = new_account_with_stake_coins(@bob, 100000000000000000);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // 1000b of coins
        let reward_coins = mint_default_coin<RewardCoin>(1000000000000000000);
        // 1 week.
        let duration = WEEK_IN_SECONDS;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake alice.
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 90000000000000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // stake bob.
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 10000000000000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);

        // harvest first time.
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@bob, coins);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // harvest second time.
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@bob, coins);

        // unstake.
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 90000000000000000);
        coin::deposit<StakeCoin>(@alice, coins);

        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 10000000000000000);
        coin::deposit<StakeCoin>(@bob, coins);
    }

    #[test]
    public fun test_stake_and_harvest_big_real_values_long_time() {
        // well, really i just want to test large numbers with 8 decimals, so this why we have billions.
        let (defiralia_staking, _) = initialize_test();

        // 900b of coins.
        let alice_acc = new_account_with_stake_coins(@alice, 900000000000000000);
        // 100b of coins.
        let bob_acc = new_account_with_stake_coins(@bob, 100000000000000000);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // 1000b of coins
        let reward_coins = mint_default_coin<RewardCoin>(1000000000000000000);
        // 10 years.
        let duration = 31536000 * 10;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake alice.
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 90000000000000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // stake bob.
        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 10000000000000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@bob, coins);

        // unstake.
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 90000000000000000);
        coin::deposit<StakeCoin>(@alice, coins);

        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 10000000000000000);
        coin::deposit<StakeCoin>(@bob, coins);
    }

    #[test]
    public fun test_premature_unstake_and_harvest() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        timestamp::update_global_time_for_test_secs(START_TIME + duration - 1);

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait until pool expired and almost a week more
        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS / 2);

        let coins = stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit(@alice, coins);

        // harvest from alice
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);

        // check amounts
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        assert!(coin::value(&coins) == 10000000, 1);

        coin::deposit<RewardCoin>(@alice, coins);
    }

    #[test]
    public fun test_stake_and_get_all_rewards_from_start_to_end() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let reward_coins_val = 157680000000000;
        let reward_coins = mint_default_coin<RewardCoin>(reward_coins_val);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // harvest from alice
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);

        // check amounts
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        assert!(coin::value(&coins) == reward_coins_val, 1);

        coin::deposit<RewardCoin>(@alice, coins);
    }

    #[test]
    public fun test_reward_is_not_accumulating_after_end() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        coin::register<RewardCoin>(&alice_acc);

        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let reward_val = stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(reward_val == 0, 1);
        assert!(accum_reward == 0, 1);
        assert!(last_updated == START_TIME, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let reward_val = stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(reward_val == 78840000000000, 1);
        assert!(accum_reward == 788400000000000000, 1);
        assert!(last_updated == START_TIME + duration / 2, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let reward_val = stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(reward_val == 157680000000000, 1);
        assert!(accum_reward == 1576800000000000000, 1);
        assert!(last_updated == START_TIME + duration, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 1);
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let reward_val = stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(reward_val == 157680000000000, 1);
        assert!(accum_reward == 1576800000000000000, 1);
        assert!(last_updated == START_TIME + duration, 1);

        timestamp::update_global_time_for_test_secs(START_TIME + duration + WEEK_IN_SECONDS * 200);
        stake::recalculate_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        let (_, accum_reward, last_updated, _, _) = stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        let reward_val = stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(reward_val == 157680000000000, 1);
        assert!(accum_reward == 1576800000000000000, 1);
        assert!(last_updated == START_TIME + duration, 1);
    }

    #[test]
    public fun test_pool_exists() {
        let (defiralia_staking, _) = initialize_test();

        // check pool exists before register
        let exists = stake::pool_exists<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(!exists, 1);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // check pool exists after register
        let exists = stake::pool_exists<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(exists, 1);
    }

    #[test]
    public fun test_stake_exists() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 12345);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // check stake exists before alice stake
        let exists = stake::stake_exists<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(!exists, 1);

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 12345);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // check stake exists after alice stake
        let exists = stake::stake_exists<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
        assert!(exists, 1);
    }

    #[test]
    public fun test_get_user_stake() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 50 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 50000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 50000000, 1);

        // stake 50 StakeCoins more from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 50000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 100000000, 1);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // unstake 30 StakeCoins from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 30000000);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 70000000, 1);
        coin::deposit<StakeCoin>(@alice, coins);

        // unstake all from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 70000000);
        assert!(stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
        coin::deposit<StakeCoin>(@alice, coins);
    }

    #[test]
    public fun test_get_pending_user_rewards() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // check stake earned and pool accum_reward
        let (_, accum_reward, _, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 0, 1);
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);

        // wait one week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // check stake earned
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 604800000000, 1);

        // check get_pending_user_rewards calculations didn't affect pool accum_reward
        let (_, accum_reward, _, _, _) =
            stake::get_pool_info<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(accum_reward == 0, 1);

        // unstake all 100 StakeCoins from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit(@alice, coins);

        // wait one week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS + WEEK_IN_SECONDS);

        // check stake earned didn't change a week after full unstake
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 604800000000, 1);

        // harvest from alice
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        assert!(coin::value(&coins) == 604800000000, 1);
        coin::deposit<RewardCoin>(@alice, coins);

        // check earned calculations after harvest
        assert!(stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice) == 0, 1);
    }

    #[test]
    public fun test_is_finished() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // check is finished
        assert!(!is_finished<StakeCoin, RewardCoin>(@defiralia_staking), 1);

        // wait to a second before pool duration end
        timestamp::update_global_time_for_test_secs(START_TIME + duration - 1);

        // check is finished
        assert!(!is_finished<StakeCoin, RewardCoin>(@defiralia_staking), 1);

        // wait one second
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // check is finished
        assert!(is_finished<StakeCoin, RewardCoin>(@defiralia_staking), 1);
    }

    #[test]
    public fun test_get_end_timestamp() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // check pool expiration date
        let end_ts = stake::get_end_timestamp<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(end_ts == START_TIME + duration, 1);

        // deposit more rewards
        let reward_coins = mint_default_coin<RewardCoin>(604800000000);
        stake::deposit_reward_coins<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, reward_coins);

        // check pool expiration date
        let end_ts = stake::get_end_timestamp<StakeCoin, RewardCoin>(@defiralia_staking);
        assert!(end_ts == START_TIME + duration + 604800, 1);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_deposit_reward_coins_fails_if_pool_does_not_exist() {
        let defiralia_staking = new_account(@defiralia_staking);

        // mint reward coins
        initialize_reward_coin(&defiralia_staking, 6);
        let reward_coins = mint_default_coin<RewardCoin>(100);

        stake::deposit_reward_coins<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, reward_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_stake_fails_if_pool_does_not_exist() {
        let defiralia_staking = new_account(@defiralia_staking);

        // mint stake coins
        initialize_stake_coin(&defiralia_staking, 6);
        let stake_coins = mint_default_coin<StakeCoin>(100);

        // stake when no pool
        stake::stake<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, stake_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_unstake_fails_if_pool_does_not_exist() {
        let defiralia_staking = new_account(@defiralia_staking);

        // unstake when no pool
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, 12345);
        coin::deposit<StakeCoin>(@defiralia_staking, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_harvest_fails_if_pool_does_not_exist() {
        let defiralia_staking = new_account(@defiralia_staking);

        // harvest when no pool
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking);
        coin::deposit<RewardCoin>(@defiralia_staking, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_get_pool_total_staked_fails_if_pool_does_not_exist() {
        stake::get_pool_total_stake<StakeCoin, RewardCoin>(@defiralia_staking);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_get_user_stake_fails_if_pool_does_not_exist() {
        stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_get_pending_user_rewards_fails_if_pool_does_not_exist() {
        stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_get_unlock_time_fails_if_pool_does_not_exist() {
        stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_is_unlocked_fails_if_pool_does_not_exist() {
        stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_is_finished_fails_if_pool_does_not_exist() {
        stake::is_finished<StakeCoin, RewardCoin>(@defiralia_staking);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_POOL)]
    public fun test_get_end_timestamp_fails_if_pool_does_not_exist() {
        stake::get_end_timestamp<StakeCoin, RewardCoin>(@defiralia_staking);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_POOL_ALREADY_EXISTS)]
    public fun test_register_fails_if_pool_already_exists() {
        initialize_test();

        let alice_acc = new_account(@alice);

        // get reward coins
        let reward_coins_1 = mint_default_coin<RewardCoin>(12345);
        let reward_coins_2 = mint_default_coin<RewardCoin>(12345);

        // register staking pool twice
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&alice_acc, reward_coins_1, duration, option::none());
        stake::register_pool<StakeCoin, RewardCoin>(&alice_acc, reward_coins_2, duration, option::none());
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_REWARD_CANNOT_BE_ZERO)]
    public fun test_register_fails_if_reward_is_zero() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = coin::zero<RewardCoin>();
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_STAKE)]
    public fun test_get_user_stake_fails_if_stake_does_not_exist() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        stake::get_user_stake<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_STAKE)]
    public fun test_get_pending_user_rewards_fails_if_stake_does_not_exist() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        stake::get_pending_user_rewards<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_STAKE)]
    public fun test_get_unlock_time_fails_if_stake_does_not_exist() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_STAKE)]
    public fun test_is_unlocked_fails_if_stake_does_not_exist() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        stake::is_unlocked<StakeCoin, RewardCoin>(@defiralia_staking, @alice);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_STAKE)]
    public fun test_unstake_fails_if_stake_not_exists() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // unstake when stake not exists
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, 12345);
        coin::deposit<StakeCoin>(@defiralia_staking, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NO_STAKE)]
    public fun test_harvest_fails_if_stake_not_exists() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // harvest when stake not exists
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking);
        coin::deposit<RewardCoin>(@defiralia_staking, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NOT_ENOUGH_S_BALANCE)]
    public fun test_unstake_fails_if_not_enough_balance() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 99000000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 99 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 99000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait one week to unstake
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS);

        // unstake more than staked from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 99000001);
        coin::deposit<StakeCoin>(@alice, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_AMOUNT_CANNOT_BE_ZERO)]
    public fun test_stake_fails_if_amount_is_zero() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 0 StakeCoins
        coin::register<StakeCoin>(&defiralia_staking);
        let coins =
            coin::withdraw<StakeCoin>(&defiralia_staking, 0);
        stake::stake<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_AMOUNT_CANNOT_BE_ZERO)]
    public fun test_unstake_fails_if_amount_is_zero() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // unstake 0 StakeCoins
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, 0);
        coin::deposit<StakeCoin>(@defiralia_staking, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_AMOUNT_CANNOT_BE_ZERO)]
    public fun test_deposit_reward_coins_fails_if_amount_is_zero() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // deposit 0 RewardCoins
        let reward_coins = coin::zero<RewardCoin>();
        stake::deposit_reward_coins<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, reward_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NOTHING_TO_HARVEST)]
    public fun test_harvest_fails_if_nothing_to_harvest_1() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // harvest from alice at the same second
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@alice, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NOTHING_TO_HARVEST)]
    public fun test_harvest_fails_if_nothing_to_harvest_2() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 100000000);

        coin::register<RewardCoin>(&alice_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait 10 seconds
        timestamp::update_global_time_for_test_secs(START_TIME + 10);

        // harvest from alice twice at the same second
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@alice, coins);
        let coins =
            stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit<RewardCoin>(@alice, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_IS_NOT_COIN)]
    public fun test_register_fails_if_stake_coin_is_not_coin() {
        genesis::setup();

        let defiralia_staking = new_account(@defiralia_staking);

        // create only reward coin
        initialize_reward_coin(&defiralia_staking, 6);

        // register staking pool without stake coin
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_IS_NOT_COIN)]
    public fun test_register_fails_if_reward_coin_is_not_coin() {
        genesis::setup();

        let defiralia_staking = new_account(@defiralia_staking);

        // create only stake coin
        initialize_stake_coin(&defiralia_staking, 6);

        // register staking pool with rewards
        let reward_coins = coin::zero<RewardCoin>();
        let duration = 12345;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_TOO_EARLY_UNSTAKE)]
    public fun test_unstake_fails_if_executed_before_lockup_end() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 1000000);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 1000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        // wait almost a week
        timestamp::update_global_time_for_test_secs(START_TIME + WEEK_IN_SECONDS - 1);

        // unstake from alice
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 1000000);
        coin::deposit(@alice, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_DURATION_CANNOT_BE_ZERO)]
    public fun test_register_fails_if_duration_is_zero() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(12345);
        let duration = 0;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_DURATION_CANNOT_BE_ZERO)]
    public fun test_deposit_reward_coins_fails_if_duration_is_zero() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // deposit rewards less than rew_per_sec pool rate
        let reward_coins = mint_default_coin<RewardCoin>(999999);
        stake::deposit_reward_coins<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, reward_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_HARVEST_FINISHED)]
    public fun test_deposit_reward_coins_fails_after_harvest_is_finished() {
        let (defiralia_staking, _) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // deposit rewards less than rew_per_sec pool rate
        let reward_coins = mint_default_coin<RewardCoin>(1000000);
        stake::deposit_reward_coins<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, reward_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_HARVEST_FINISHED)]
    public fun test_stake_fails_after_harvest_is_finished() {
        let (defiralia_staking, _) = initialize_test();

        let alice_acc = new_account_with_stake_coins(@alice, 12345);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // wait until pool expired
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // stake from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 12345);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);
    }

    #[test]
    #[expected_failure(abort_code = stake_config::ERR_NOT_INITIALIZED /* ERR_NOT_INITIALIZED */)]
    fun test_register_without_config_initialization_fails() {
        let defiralia_staking = new_account(@defiralia_staking);
        initialize_stake_coin(&defiralia_staking, 6);
        initialize_reward_coin(&defiralia_staking, 6);

        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());
    }

    // Withdraw rewards tests.

    #[test]
    #[expected_failure(abort_code = stake::ERR_NOT_WITHDRAW_PERIOD)]
    fun test_withdraw_fails_non_emergency_or_finish() {
        let (defiralia_staking, _) = initialize_test();
        let treasury = new_account(@treasury);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        let reward_coins = stake::withdraw_to_treasury<StakeCoin, RewardCoin>(&treasury, @defiralia_staking, 157680000000000);
        coin::deposit(@treasury, reward_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NOT_TREASURY)]
    fun test_withdraw_fails_from_non_treasury_account() {
        let (defiralia_staking, emergency) = initialize_test();

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency);

        let reward_coins = stake::withdraw_to_treasury<StakeCoin, RewardCoin>(&defiralia_staking, @defiralia_staking, 157680000000000);
        coin::deposit(@defiralia_staking, reward_coins);
    }

    #[test]
    fun test_withdraw_in_emergency() {
        let (defiralia_staking, emergency) = initialize_test();
        let treasury = new_account(@treasury);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        stake_config::enable_global_emergency(&emergency);

        let reward_coins = stake::withdraw_to_treasury<StakeCoin, RewardCoin>(&treasury, @defiralia_staking, 157680000000000);
        assert!(coin::value(&reward_coins) == 157680000000000, 1);
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);
    }

    #[test]
    fun test_withdraw_after_period() {
        let (defiralia_staking, _) = initialize_test();
        let treasury = new_account(@treasury);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257600);

        let reward_coins = stake::withdraw_to_treasury<StakeCoin, RewardCoin>(&treasury, @defiralia_staking, 157680000000000);
        assert!(coin::value(&reward_coins) == 157680000000000, 1);
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);
    }

    #[test]
    fun test_withdraw_after_period_plus_emergency() {
        let (defiralia_staking, emergency) = initialize_test();
        let treasury = new_account(@treasury);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257600);
        stake_config::enable_global_emergency(&emergency);

        let reward_coins = stake::withdraw_to_treasury<StakeCoin, RewardCoin>(&treasury, @defiralia_staking, 157680000000000);
        assert!(coin::value(&reward_coins) == 157680000000000, 1);
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);
    }

    #[test]
    #[expected_failure(abort_code = stake::ERR_NOT_WITHDRAW_PERIOD)]
    fun test_withdraw_fails_before_period() {
        let (defiralia_staking, _) = initialize_test();
        let treasury = new_account(@treasury);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(157680000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257599);

        let reward_coins = stake::withdraw_to_treasury<StakeCoin, RewardCoin>(&treasury, @defiralia_staking, 157680000000000);
        coin::deposit(@treasury, reward_coins);
    }

    #[test]
    fun test_withdraw_and_unstake() {
        // i check users can unstake after i withdraw all rewards in 3 months.
        let (defiralia_staking, _) = initialize_test();

        let treasury = new_account(@treasury);
        let alice_acc = new_account_with_stake_coins(@alice, 100000000);
        let bob_acc = new_account_with_stake_coins(@bob, 5000000000);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        // register staking pool with rewards
        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        // stake 100 StakeCoins from alice
        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 5000000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        // wait 3 months after finish
        timestamp::update_global_time_for_test_secs(START_TIME + duration + 7257600);

        // waithdraw reward coins
        let reward_coins = stake::withdraw_to_treasury<StakeCoin, RewardCoin>(&treasury, @defiralia_staking, 15768000000000);
        coin::register<RewardCoin>(&treasury);
        coin::deposit(@treasury, reward_coins);

        // unstake
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit(@alice, coins);

        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 5000000000);
        coin::deposit(@bob, coins);
    }

    #[test]
    fun test_stake_after_full_unstake() {
        let (defiralia_staking, _) = initialize_test();
        let alice_acc = new_account_with_stake_coins(@alice, 100000000);
        let bob_acc = new_account_with_stake_coins(@bob, 5000000000);

        coin::register<RewardCoin>(&alice_acc);
        coin::register<RewardCoin>(&bob_acc);

        let reward_coins = mint_default_coin<RewardCoin>(15768000000000);
        let duration = 15768000;
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        let coins =
            coin::withdraw<StakeCoin>(&bob_acc, 100000000);
        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        timestamp::update_global_time_for_test_secs(START_TIME + duration / 2);

        let coins = stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 100000000);

        timestamp::update_global_time_for_test_secs(START_TIME + (duration / 2 + 3600));

        stake::stake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, coins);

        let unlock_time = stake::get_unlock_time<StakeCoin, RewardCoin>(@defiralia_staking, @bob);
        assert!(unlock_time == timestamp::now_seconds() + WEEK_IN_SECONDS, 1);
        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        // take rewards.
        let rewards = stake::harvest<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking);
        assert!(coin::value(&rewards) == 7882200000000, 1);
        coin::deposit(@bob, rewards);

        let rewards = stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        assert!(coin::value(&rewards) == 7885800000000, 1);
        coin::deposit(@alice, rewards);

        // unstake.
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit(@alice, coins);

        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&bob_acc, @defiralia_staking, 100000000);
        coin::deposit(@bob, coins);
    }

    #[test]
    fun test_stake_aptos_real_value() {
        // We need to stake Aptos on 20k USD (it's 6060 APT = 8 decimals).
        // Than we need to check how it will work with 30M LP coins (6 decimals).
        // We just checking it not fails, because if it fails, it means it's possible to block rewards.

        let duration = 7890000;
        let (defiralia_staking, _) = initialize_test();
        let alice_acc = new_account_with_stake_coins(@alice, 30000000000000 + duration);

        coin::register<RewardCoin>(&alice_acc);

        let reward_coins = mint_default_coin<RewardCoin>(606000000000);
        stake::register_pool<StakeCoin, RewardCoin>(&defiralia_staking, reward_coins, duration, option::none());

        let coins =
            coin::withdraw<StakeCoin>(&alice_acc, 30000000000000);

        stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

        let i = 1;
        while (i <= 3600) {
            timestamp::update_global_time_for_test_secs(START_TIME + i);

            let coins = coin::withdraw<StakeCoin>(&alice_acc, 1);
            stake::stake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, coins);

            i = i + 1;
        };

        // take rewards.
        let rewards = stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit(@alice, rewards);

        timestamp::update_global_time_for_test_secs(START_TIME + duration);

        let rewards = stake::harvest<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking);
        coin::deposit(@alice, rewards);

        // unstake.
        let coins =
            stake::unstake<StakeCoin, RewardCoin>(&alice_acc, @defiralia_staking, 100000000);
        coin::deposit(@alice, coins);
    }
}
