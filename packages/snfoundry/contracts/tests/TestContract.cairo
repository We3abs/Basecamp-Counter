// import libraries
use contracts::counter::Counter::FELT_STRK_CONTRACT;
use contracts::counter::{
    Counter, ICounterDispatcher, ICounterDispatcherTrait, ICounterSafeDispatcher,
    ICounterSafeDispatcherTrait
};

// OZ libraries
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher,IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress};

const ZERO_COUNT: u32 = 0;
const STRK_AMOUNT: u256 = 5000000000000000000; //5 strk
const WIN_NUMBER: u32 = 10;

// Test Accounts
fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER_1'.try_into().unwrap()
}

fn STRK() -> ContractAddress{
    FELT_STRK_CONTRACT.try_into().unwrap()
}

pub const STRK_TOKEN_HOLDER_ADDRESS: felt252= 
    0x069a62bdc4652444f41cdfab856b60e3a0907542cda46c9844fedc08699ef983;

fn STRK_TOKEN_HOLDER() -> ContractAddress {
    STRK_TOKEN_HOLDER_ADDRESS.try_into().unwrap()
}




// util deploy function
fn __deploy__(init_value: u32) -> (ICounterDispatcher, IOwnableDispatcher, ICounterSafeDispatcher,IERC20Dispatcher) {
    // declare contract
    let contract_class = declare("Counter").expect('failed to declare').contract_class();

    // serialize constructor args
    let mut calldata: Array<felt252> = array![];
    init_value.serialize(ref calldata);
    OWNER().serialize(ref calldata);

    // deploy contract
    let (contract_address, _) = contract_class.deploy(@calldata).expect('failed to deploy');

    // return values
    let counter = ICounterDispatcher { contract_address };
    let ownable = IOwnableDispatcher { contract_address };
    let safe_dispatcher = ICounterSafeDispatcher { contract_address };
    let strk_token= IERC20Dispatcher{contract_address: STRK() };


    transfer_strk(STRK_TOKEN_HOLDER(), contract_address, STRK_AMOUNT);
    (counter, ownable, safe_dispatcher, strk_token)
}

fn get_strk_token_balance(account: ContractAddress) -> u256 {
    IERC20Dispatcher{ contract_address: STRK() }.balance_of(account)
}

fn transfer_strk(caller: ContractAddress, recipient: ContractAddress, amount:u256){
    start_cheat_caller_address(STRK(), caller);
    let token_dispatcher = IERC20Dispatcher{contract_address: STRK()};
    token_dispatcher.transfer(recipient, amount);
    stop_cheat_caller_address(STRK());
}

fn approve_strk(owner: ContractAddress, spender: ContractAddress, amount: u256){
    start_cheat_caller_address(STRK(), owner);
    let token_dispatcher= IERC20Dispatcher{contract_address:STRK()};
    token_dispatcher.approve(spender, amount);
    stop_cheat_caller_address(STRK());
}


#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_counter_deployment() {
    let (counter, ownable, _, _) = __deploy__(ZERO_COUNT);
    // get current count
    let count_1 = counter.get_counter();

   
    assert(count_1 == ZERO_COUNT, 'count not set');  // Verify that the counter value is by exactly 0.
    assert(ownable.owner() == OWNER(), 'owner not set');  // Verify that the counter contract owner matches our Test Owner account
}

#[test]
#[fork("MAINNET_LATEST", block_tag : latest)]
fn test_increase_counter() {
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);
    // get current count
    let count_1 = counter.get_counter();

    // assertions
    assert(count_1 == ZERO_COUNT, 'count not set');

    // state-changing txn
    counter.increase_counter();

    // retrieve current count
    let count_2 = counter.get_counter();

    // assert that count increased by 1
    assert(count_2 == count_1 + 1, 'invalid count');
}


#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_emitted_increased_event() {
    // Deploy the `counter` contract starting from ZERO_COUNT (usually 0).
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);

    // Create a spy instance to capture and inspect emitted events during the test.
    let mut spy = spy_events();

    // Simulate a transaction coming from USER_1 by setting them as the caller.
    start_cheat_caller_address(counter.contract_address, USER_1());

    // Call the `increase_counter` function — this should emit an `Increased` event.
    counter.increase_counter();

    // Stop mocking the caller address to clean up the test context.
    stop_cheat_caller_address(counter.contract_address);

    // Check that the correct `Increased` event was emitted, tied to USER_1's address.
    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
            ],
        );

    // Also verify that no `Decreased` event was accidentally emitted.
    // This ensures only the intended event occurred during the increase_counter txn.
    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
                ),
            ],
        )
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
    fn test_increase_counter_contract_transfers_strk_to_caller_when_counter_is_a_win_number() {
        let(counter, _, _, _) =__deploy__(9);
        // get current count
        let count_1 = counter.get_counter();
        // validations
        assert(count_1 == 9, 'count not set');

        // validate counter contract strk token balance
        let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);
        assert(counter_strk_balance_1== STRK_AMOUNT, 'invalid counter balance');



        // validete counter contract strk token balanace
        let user1_strk_balance_1 = get_strk_token_balance(USER_1());

        assert(user1_strk_balance_1 == 0, 'invalid user1 balance');
        // simulate a transaction 

        start_cheat_caller_address(counter.contract_address, USER_1());
        start_cheat_caller_address(STRK(), counter.contract_address);

        let win_number: u32 = counter.get_win_number();

        assert(win_number == 10, 'invalid win number');

        counter.increase_counter();

        stop_cheat_caller_address(counter.contract_address);
        stop_cheat_caller_address(STRK());

        //retrieve current count
        let count_2 = counter.get_counter();
        assert(count_2 == 10, 'count 2 not set');

        //check if all 5 strk tokens in counter contract was succesfull transferred
        let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
        assert(counter_strk_balance_2 == 0, 'invalid STRK balance');

        let user_1_strk_token_balance = get_strk_token_balance(USER_1());
        assert(user_1_strk_token_balance== STRK_AMOUNT, 'strk not transferred');


    }


#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_increase_counter_does_not_transfer_strk_token_to_caller_when_counter_has_zero_strk(){
    let test_count: u32 = 9;
    let (counter, _, _, _)= __deploy__(test_count);
    let counter_address= counter.contract_address;
    //get current count 
     let count_1 = counter.get_counter();

     //assertions 
     assert(count_1 == test_count, 'count not set');

     // Strk token balances
     let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);

     //check if ocunter contract has the 5 strk balance
     assert(counter_strk_balance_1 == STRK_AMOUNT, ' invalid counter balance');
     let owner_strk_balance_1 = get_strk_token_balance(OWNER());
     assert(owner_strk_balance_1 == 0, 'invalid owner strk amount');

     //transfer out all 5 strk tokens to owner
     transfer_strk(counter.contract_address, OWNER(), STRK_AMOUNT);

     //validate that transfer was successful from counter to Owner
     let counter_balance_after_transfer_to_owner: u256 = get_strk_token_balance(counter_address);
     assert(counter_balance_after_transfer_to_owner== 0, 'not transferred to owner');
    

    // validate that owner strk balance increased
    let owner_strk_balance: u256 = get_strk_token_balance(OWNER());
    assert(owner_strk_balance == STRK_AMOUNT, 'owner balance not increased');

    start_cheat_caller_address(counter.contract_address, USER_1());
    let win_number_1: u32 = counter.get_win_number();


    // validate win number
    assert(win_number_1== 10, 'invalid win number');

    // // state-changing txn increase counter by user1
    counter.increase_counter();

    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2== test_count + 1, 'count 2 not set');

    let strk_bal_user_1: u256 = get_strk_token_balance(USER_1());
    assert(strk_bal_user_1 == 0 , ' strk bal cannot increase');

    let counter_strk_balance_2: u256 = get_strk_token_balance(counter_address);
    assert(counter_strk_balance_2 == 0, 'counter strk bal unchanged');

}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
#[feature("safe_dispatcher")]
fn test_safe_panic_decrease_counter(){
    let (counter, _, safe_dispatcher, _)= __deploy__(ZERO_COUNT);
    assert(counter.get_counter( )== ZERO_COUNT,'invalid count');

    match safe_dispatcher.decrease_counter() {
        Result::Ok(_)=>panic!("cannot decrease to 0"),
        Result::Err(e) => assert(*e[0]== 'Decreasing Empty counter',*e.at(0)),

    }
}


#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
#[should_panic(expected: 'Decreasing Empty counter')]
fn test_panic_decrease_counter(){
    let (counter, _, _, _)= __deploy__(ZERO_COUNT);

    assert (counter.get_counter() == ZERO_COUNT, 'invalid count');

    counter.decrease_counter()
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_successful_decrease_counter() {
    let (counter, _,_,_)= __deploy__(5);
    let count_1 = counter.get_counter();
    assert(count_1== 5, 'invalid count');

    counter.decrease_counter();
    let count_2 = counter.get_counter();
    assert(count_2== count_1 - 1, ' invalid decrease count');
}




#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_succesful_reset_counter(){
    let test_count: u32 = 5;
    let (counter, _, _, strk_token)= __deploy__(test_count);

    let mut spy = spy_events();

    let test_strk_amount: u256 =10000000000000000000;

    let count_1 =counter.get_counter();

    assert(count_1 ==5, 'invalid count');
    approve_strk(USER_1(), counter.contract_address, test_strk_amount);

    let counter_allowance = strk_token.allowance(USER_1(), counter.contract_address);
    assert(counter_allowance == test_strk_amount, 'failed to approve');
    let strk_holder_balance : u256 =get_strk_token_balance(STRK_TOKEN_HOLDER());
    assert (strk_holder_balance > test_strk_amount, 'insufficient STRK');

    transfer_strk(STRK_TOKEN_HOLDER(), USER_1(), test_strk_amount);

    let counter_strk_balance = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance == STRK_AMOUNT, 'invalid strk balance');

    let user1_strk_balance_1: u256 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_1 == test_strk_amount, 'strk not transfered');

    

    start_cheat_caller_address(counter.contract_address, USER_1());

    counter.reset_counter();

    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == 0, 'counter not reset');

    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == STRK_AMOUNT + STRK_AMOUNT, 'no strk transferred');

    let user1_strk_balance_2 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_2 == test_strk_amount - STRK_AMOUNT, 'strk not deducted');

    spy 
    .assert_emitted(
        @array![
            (
                counter.contract_address,
                Counter::Event::Reset(Counter::Reset{account: USER_1() }),
            ),
        ],
    );

    spy 
    .assert_not_emitted(
        @array![
            (
                counter.contract_address,
                Counter::Event::Increased(Counter::Increased{account: USER_1() }),
            ),
        ],
    );
}


#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_reset_counter_contract_receives_no_strk_token_when_strk_balance_is_zero() {
    let (counter, _, _, _) = __deploy__(9);
    // get current count
    let count_1 = counter.get_counter();

    let counter_address = counter.contract_address;

    assert(count_1== 9, 'count not set');
    let counter_strk_balance_1 = get_strk_token_balance(counter_address);

    assert (counter_strk_balance_1 == STRK_AMOUNT, 'invalid counter balance');

    let user_1_strk_balance_1 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_1 == 0, 'invalide user1 strk bal');

    start_cheat_caller_address(counter.contract_address, USER_1());
    start_cheat_caller_address(STRK(), counter.contract_address);

    let win_number: u32 = counter.get_win_number();

    assert (win_number==10, 'invalid win number');

    counter.increase_counter();

    stop_cheat_caller_address(counter.contract_address);
    stop_cheat_caller_address(STRK());

    let count_2 = counter.get_counter();
    assert(count_2 == 10, ' count 2 not set');
    let counter_strk_balance_2= get_strk_token_balance(counter_address);
    assert(counter_strk_balance_2== 0 , 'invalid counter 2 strk balance');





    let user_1_strk_token_balance = IERC20Dispatcher{contract_address: STRK()}
    .balance_of(USER_1());
    assert (user_1_strk_token_balance == STRK_AMOUNT, 'strk not transferred');
    start_cheat_caller_address(counter.contract_address, USER_1());

    counter.reset_counter();

    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == 0 , 'failed to reset count');

    let counter_strk_balance_2= get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'no strk transfered');
    let user1_strk_balance_2 = get_strk_token_balance(USER_1());

    assert(user1_strk_balance_2 == STRK_AMOUNT, 'strk not deducted')
    
}

