const std = @import("std");
const builtin = @import("builtin");
const td = @cImport({
    @cInclude("td/telegram/td_json_client.h");
});
const test_allocator = std.testing.allocator;

pub fn main() !void {
    const client_id = td.td_create_client_id();

    td.td_send(client_id,
        \\{ "@type": "getAuthorizationState",  "@extra": 1.01234 }
    );

    while (td.td_receive(1.0)) |td_received| {
        const received = std.mem.sliceTo(td_received, 0);

        std.debug.print("{s}", .{received});

        var json_parser = std.json.Parser.init(test_allocator, false);
        defer json_parser.deinit();

        var tree = try json_parser.parse(received);
        defer tree.deinit();

        var response_type = tree.root.Object.get("@type").?;

        if (std.mem.eql(u8, response_type.String, "updateAuthorizationState")) {
            const auth_state = tree.root.Object.get("authorization_state").?;

            const auth_state_response_type = auth_state.Object.get("@type").?;

            if (std.mem.eql(u8, auth_state_response_type.String, "authorizationStateClosed")) {
                break;
            }

            if (std.mem.eql(u8, auth_state_response_type.String, "authorizationStateWaitTdlibParameters")) {
                td.td_send(client_id,
                    \\{
                    \\    "@type": "setTdlibParameters",
                    \\    "parameters": {
                    \\        "database_directory": "tdlib",
                    \\        "use_message_database": true,
                    \\        "use_secret_chats": true,
                    \\        "api_id": 0,
                    \\        "api_hash": "0",
                    \\        "system_language_code": "en",
                    \\        "device_model": "Desktop",
                    \\        "application_version": "1.0",
                    \\        "enable_storage_optimizer": true
                    \\    }
                    \\}
                );
            }

            if (std.mem.eql(u8, auth_state_response_type.String, "authorizationStateWaitEncryptionKey")) {
                td.td_send(client_id,
                    \\{"@type": "checkDatabaseEncryptionKey", "encryption_key": "DERP"}
                );
            }

            if (std.mem.eql(u8, auth_state_response_type.String, "authorizationStateWaitPhoneNumber")) {
                const stdout = std.io.getStdOut();
                const stdin = std.io.getStdIn();

                try stdout.writeAll(
                    \\ Enter your telephone number:
                );

                var buffer: [100]u8 = undefined;
                const input = (try nextLine(stdin.reader(), &buffer)).?;

                var json: [100]u8 = undefined;
                const json_slice = json[0..];

                const formatted = try std.fmt.bufPrint(
                    json_slice,
                    "{s}{s}{s}",
                    .{
                        \\{"@type": "setAuthenticationPhoneNumber", "phone_number": 
                        ,
                        input,
                        \\}
                        ,
                    },
                );

                td.td_send(client_id, @ptrCast([*c]const u8, formatted));
            }
        }

        if (std.mem.eql(u8, response_type.String, "updateNewMessage")) {
            std.debug.print("SHOW ME", .{});
        }
    }
}

fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(
        buffer,
        '\n',
    )) orelse return null;
    // trim annoying windows-only carriage return character
    if (builtin.os.tag == .windows) {
        line = std.mem.trimRight(u8, line, "\r");
    }
    return line;
}
