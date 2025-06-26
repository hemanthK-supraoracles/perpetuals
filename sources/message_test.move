// #[test_only]
// module perps::message_tests {
//     use std::string;
//     use std::signer;
//     use aptos_framework::account;
//     use perps::message;

//     #[test]
//     fun test_set_and_get_message() {
//         // Set up test account
//         let test_account = account::create_account_for_test(@0x1);

//         // Test setting a message
//         message::set_message(&test_account, string::utf8(b"Hello World"));

//         // Verify the message was set correctly
//         let stored_message = message::get_message(signer::address_of(&test_account));
//         assert!(stored_message == string::utf8(b"Hello World"), 0);
//     }
// }
