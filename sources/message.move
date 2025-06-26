// module perps::message {
//     use std::string;
//     use std::signer;
//     use std::debug;  // Add this for debug prints

//     struct MessageHolder has key, store, drop {
//         message: string::String,
//     }

//     public entry fun set_message(account: &signer, message: string::String) acquires MessageHolder {
//         let account_addr = signer::address_of(account);
//         debug::print(&message); // Print the message being set

//         if (exists<MessageHolder>(account_addr)) {
//             debug::print(&b"Updating existing message"); // Print debug info
//             move_from<MessageHolder>(account_addr);
//         } else {
//             debug::print(&b"Creating new message"); // Print when creating new
//         };

//         move_to(account, MessageHolder { message });
//     }

//     public fun get_message(account_addr: address): string::String acquires MessageHolder {
//         assert!(exists<MessageHolder>(account_addr), 0);
//         let message_holder = borrow_global<MessageHolder>(account_addr);
//         debug::print(&message_holder.message); // Print the retrieved message
//         message_holder.message
//     }
// }
