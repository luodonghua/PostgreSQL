#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <stdint.h>
#include <arpa/inet.h>
#include <krb5.h>

// PAC structure definitions based on MS-PAC specification
#define PACTYPE_LOGON_INFO        1
#define PACTYPE_CREDENTIALS_INFO  2
#define PACTYPE_SERVER_CHECKSUM  6
#define PACTYPE_PRIVSVR_CHECKSUM 7
#define PACTYPE_CLIENT_INFO      10

// Authorization data type for Windows PAC
#ifndef KRB5_AUTHDATA_WIN2K_PAC
#define KRB5_AUTHDATA_WIN2K_PAC 128
#endif

// Custom error code for no PAC data
#define KRB5_PAC_NOT_FOUND (-1)

// Group membership attributes
#define SE_GROUP_MANDATORY          0x00000001
#define SE_GROUP_ENABLED_BY_DEFAULT 0x00000002
#define SE_GROUP_ENABLED            0x00000004
#define SE_GROUP_OWNER             0x00000008
#define SE_GROUP_RESOURCE          0x20000000
#define SE_GROUP_INTEGRITY         0x40000000

#pragma pack(push, 1)
typedef struct _PAC_INFO_BUFFER {
    uint32_t ulType;
    uint32_t cbBufferSize;
    uint64_t Offset;
} PAC_INFO_BUFFER;

typedef struct _GROUP_MEMBERSHIP {
    uint32_t RelativeId;
    uint32_t Attributes;
} GROUP_MEMBERSHIP;

typedef struct _KERB_VALIDATION_INFO {
    uint64_t LogonTime;
    uint32_t UserId;
    uint32_t PrimaryGroupId;
    uint32_t GroupCount;
    GROUP_MEMBERSHIP *GroupIds;
} KERB_VALIDATION_INFO;
#pragma pack(pop)

static void dump_auth_data(krb5_authdata **authdata) {
    if (!authdata) return;
    
    printf("Authorization Data:\n");
    for (int i = 0; authdata[i]; i++) {
        printf("Type: %d, Length: %u\n", 
               authdata[i]->ad_type, 
               (unsigned int)authdata[i]->length);
        
        // If this is PAC data, print additional information
        if (authdata[i]->ad_type == KRB5_AUTHDATA_WIN2K_PAC) {
            printf("Found PAC data\n");
            printf("PAC data (first 16 bytes): ");
            for (int j = 0; j < 16 && j < authdata[i]->length; j++) {
                printf("%02x ", (unsigned char)authdata[i]->contents[j]);
            }
            printf("\n");
        }
    }
}

static void print_encryption_info(krb5_context context, krb5_ticket *ticket) {
    if (ticket && ticket->enc_part.enctype) {
        char enctype_buf[100];
        krb5_error_code ret = krb5_enctype_to_name(ticket->enc_part.enctype, 
                                                  FALSE, 
                                                  enctype_buf, 
                                                  sizeof(enctype_buf));
        if (ret == 0) {
            printf("Encryption Type: %s (value: %d)\n", 
                   enctype_buf, ticket->enc_part.enctype);
        } else {
            printf("Encryption Type: Unknown (value: %d)\n", 
                   ticket->enc_part.enctype);
        }
    }
}

static void print_key_info(krb5_context context, krb5_keyblock *key) {
    if (!key) return;

    char enctype_buf[100];
    krb5_error_code ret = krb5_enctype_to_name(key->enctype, 
                                              FALSE, 
                                              enctype_buf, 
                                              sizeof(enctype_buf));
    
    printf("Key Information:\n");
    printf("  Encryption Type: %s (value: %d)\n", 
           (ret == 0) ? enctype_buf : "Unknown", 
           key->enctype);
    printf("  Key Length: %d bytes\n", key->length);
}

static void print_addresses(krb5_context context, krb5_address **addresses) {
    if (!addresses) return;

    printf("Addresses:\n");
    for (int i = 0; addresses[i]; i++) {
        char buf[128];
        switch (addresses[i]->addrtype) {
            case ADDRTYPE_INET:
                if (inet_ntop(AF_INET, addresses[i]->contents, buf, sizeof(buf))) {
                    printf("  IPv4: %s\n", buf);
                }
                break;
            case ADDRTYPE_INET6:
                if (inet_ntop(AF_INET6, addresses[i]->contents, buf, sizeof(buf))) {
                    printf("  IPv6: %s\n", buf);
                }
                break;
            default:
                printf("  Address type %d, length %d\n", 
                       addresses[i]->addrtype, addresses[i]->length);
        }
    }
}

static void print_transited_realms(krb5_context context, krb5_transited *tr) {
    if (!tr || !tr->tr_contents.data || tr->tr_contents.length == 0) return;

    printf("Transited Realms:\n");
    printf("  Type: %d\n", tr->tr_type);
    printf("  Contents length: %d\n", (int)tr->tr_contents.length);
    printf("  Contents: ");
    for (int i = 0; i < tr->tr_contents.length && i < 32; i++) {
        printf("%02x ", (unsigned char)tr->tr_contents.data[i]);
    }
    printf("\n");
}

static void print_ticket_flags_detailed(krb5_flags flags) {
    struct {
        krb5_flags flag;
        const char *name;
        const char *description;
    } flag_info[] = {
        {TKT_FLG_INITIAL, "INITIAL", "Ticket was issued using AS exchange"},
        {TKT_FLG_FORWARDABLE, "FORWARDABLE", "Ticket can be forwarded"},
        {TKT_FLG_FORWARDED, "FORWARDED", "Ticket was forwarded"},
        {TKT_FLG_PROXIABLE, "PROXIABLE", "Ticket can be used for proxy"},
        {TKT_FLG_PROXY, "PROXY", "Ticket is a proxy"},
        {TKT_FLG_MAY_POSTDATE, "MAY_POSTDATE", "Ticket can be postdated"},
        {TKT_FLG_POSTDATED, "POSTDATED", "Ticket is postdated"},
        {TKT_FLG_INVALID, "INVALID", "Ticket is invalid"},
        {TKT_FLG_RENEWABLE, "RENEWABLE", "Ticket can be renewed"},
        {TKT_FLG_PRE_AUTH, "PRE_AUTH", "Pre-authentication was used"},
        {TKT_FLG_HW_AUTH, "HW_AUTH", "Hardware authentication was used"},
        {0, NULL, NULL}
    };

    printf("Ticket Flags Detail:\n");
    for (int i = 0; flag_info[i].name; i++) {
        if (flags & flag_info[i].flag) {
            printf("  %-12s: %s\n", flag_info[i].name, flag_info[i].description);
        }
    }
}

static void print_times_detailed(krb5_ticket_times *times) {
    time_t auth_time = (time_t)times->authtime;
    time_t start_time = (time_t)times->starttime;
    time_t end_time = (time_t)times->endtime;
    time_t renew_till = (time_t)times->renew_till;
    char time_str[64];
    time_t now = time(NULL);

    printf("Time Information:\n");
    
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", localtime(&auth_time));
    printf("  Authentication Time: %s\n", time_str);
    
    if (times->starttime) {
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", localtime(&start_time));
        printf("  Start Time: %s", time_str);
        printf(" (%s)\n", start_time > now ? "not yet valid" : "valid");
    }
    
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", localtime(&end_time));
    printf("  End Time: %s", time_str);
    printf(" (%s)\n", end_time < now ? "expired" : "valid");
    
    if (times->renew_till) {
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", localtime(&renew_till));
        printf("  Renewable Until: %s", time_str);
        printf(" (%s)\n", renew_till < now ? "expired" : "valid");
    }

    printf("\nDurations:\n");
    if (times->starttime) {
        printf("  Ticket lifetime: %.1f hours\n", 
               difftime(end_time, start_time) / 3600.0);
    }
    if (times->renew_till) {
        printf("  Renewable lifetime: %.1f hours\n", 
               difftime(renew_till, times->starttime ? start_time : auth_time) / 3600.0);
    }
}

static void print_ticket_info(krb5_context context, krb5_ticket *ticket) {
    if (!ticket) {
        printf("Error: Ticket is NULL\n");
        return;
    }

    printf("\n=== Ticket Details ===\n\n");

    // Debug information
    printf("Ticket structure status:\n");
    printf("- Ticket pointer: %p\n", (void*)ticket);
    printf("- enc_part2 pointer: %p\n", (void*)ticket->enc_part2);
    
    // Print encryption info
    print_encryption_info(context, ticket);

    if (!ticket->enc_part2) {
        printf("\nError: Ticket encrypted part (enc_part2) is NULL\n");
        printf("This might indicate that the ticket hasn't been properly decrypted.\n");
        return;
    }

    // Print session key info
    if (ticket->enc_part2) {
        printf("\nSession Key Information:\n");
        print_key_info(context, ticket->enc_part2->session);  // Removed & operator
    }

    // Print client principal
    if (ticket->enc_part2 && ticket->enc_part2->client) {
        char *client_name = NULL;
        krb5_error_code ret = krb5_unparse_name(context, ticket->enc_part2->client, &client_name);
        if (ret == 0 && client_name) {
            printf("\nClient Principal: %s\n", client_name);
            krb5_free_unparsed_name(context, client_name);
        }
    }

    // Print server principal
    if (ticket->server) {
        char *server_name = NULL;
        krb5_error_code ret = krb5_unparse_name(context, ticket->server, &server_name);
        if (ret == 0 && server_name) {
            printf("Server Principal: %s\n", server_name);
            krb5_free_unparsed_name(context, server_name);
        }
    }

    // Print ticket flags (both simple and detailed)
    if (ticket->enc_part2) {
        krb5_flags flags = ticket->enc_part2->flags;
        printf("\nTicket Flags (Simple Format):\n");
        if (flags & TKT_FLG_INITIAL) printf("  - Initial ticket\n");
        if (flags & TKT_FLG_FORWARDABLE) printf("  - Forwardable\n");
        if (flags & TKT_FLG_FORWARDED) printf("  - Forwarded\n");
        if (flags & TKT_FLG_PROXIABLE) printf("  - Proxiable\n");
        if (flags & TKT_FLG_PROXY) printf("  - Proxy\n");
        if (flags & TKT_FLG_MAY_POSTDATE) printf("  - May postdate\n");
        if (flags & TKT_FLG_POSTDATED) printf("  - Postdated\n");
        if (flags & TKT_FLG_INVALID) printf("  - Invalid\n");
        if (flags & TKT_FLG_RENEWABLE) printf("  - Renewable\n");
        if (flags & TKT_FLG_PRE_AUTH) printf("  - Pre-authenticated\n");
        if (flags & TKT_FLG_HW_AUTH) printf("  - Hardware authenticated\n");

        printf("\nTicket Flags (Detailed Format):\n");
        print_ticket_flags_detailed(flags);
    }

    // Print time information (both simple and detailed)
        if (ticket->enc_part2) {
        krb5_ticket_times *times = &ticket->enc_part2->times;
        char time_str[64];
        time_t now = time(NULL);
        time_t auth_time = (time_t)times->authtime;    // Convert krb5_timestamp to time_t
        time_t start_time = (time_t)times->starttime;  // Convert krb5_timestamp to time_t
        time_t end_time = (time_t)times->endtime;      // Convert krb5_timestamp to time_t
        time_t renew_till = (time_t)times->renew_till; // Convert krb5_timestamp to time_t

        printf("\nTime Information (Simple Format):\n");
        
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", 
                localtime(&auth_time));
        printf("  Auth time:     %s\n", time_str);
        
        if (times->starttime) {
            strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", 
                    localtime(&start_time));
            printf("  Start time:    %s\n", time_str);
        }
        
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", 
                localtime(&end_time));
        printf("  End time:      %s\n", time_str);
        
        if (times->renew_till) {
            strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", 
                    localtime(&renew_till));
            printf("  Renew until:   %s\n", time_str);
        }

        printf("\nTime Information (Detailed Format):\n");
        print_times_detailed(times);

        // Add ticket validity status
        printf("\nTicket Status:\n");
        if (end_time < now) {
            printf("  - Ticket has expired\n");
        } else {
            printf("  - Ticket is valid\n");
        }
        
        if (times->renew_till) {
            if (renew_till < now) {
                printf("  - Renewal period has expired\n");
            } else {
                printf("  - Renewable for %.1f more hours\n", 
                       difftime(renew_till, now) / 3600.0);
            }
        }
    }

    // Print transited realms
    if (ticket->enc_part2 && ticket->enc_part2->transited.tr_contents.length > 0) {
        printf("\nTransited Realms Information:\n");
        print_transited_realms(context, &ticket->enc_part2->transited);
    }
    // Print authorization data if present
    if (ticket->enc_part2 && ticket->enc_part2->authorization_data) {
        printf("\nAuthorization Data:\n");
        dump_auth_data(ticket->enc_part2->authorization_data);
    } else {
        printf("\nAuthorization Data: Not available\n");
    }

    // Print client addresses if present
    if (ticket->enc_part2 && ticket->enc_part2->caddrs) {
        print_addresses(context, ticket->enc_part2->caddrs);
    }

    printf("\n");
}


int main() {
    krb5_context context;
    krb5_ccache ccache;
    krb5_error_code retval;
    krb5_creds mcreds, *creds = NULL;
    krb5_ticket *ticket = NULL;
    krb5_principal principal = NULL;
    char *name = NULL;
    krb5_principal copied_principal = NULL;

    // Initialize Kerberos context
    retval = krb5_init_context(&context);
    if (retval) {
        fprintf(stderr, "Error initializing Kerberos context: %s\n",
                krb5_get_error_message(context, retval));
        return 1;
    }

    // Get default credential cache
    retval = krb5_cc_default(context, &ccache);
    if (retval) {
        fprintf(stderr, "Error getting credential cache: %s\n", 
                krb5_get_error_message(context, retval));
        krb5_free_context(context);
        return 1;
    }

    // Get and print principal name
    retval = krb5_cc_get_principal(context, ccache, &principal);
    if (retval == 0) {
        retval = krb5_unparse_name(context, principal, &name);
        if (retval == 0) {
            printf("Default principal: %s\n\n", name);
            krb5_free_unparsed_name(context, name);
        }
    }

    // Initialize memory
    memset(&mcreds, 0, sizeof(mcreds));
    mcreds.client = principal;

    // Get the krbtgt principal for the realm
    retval = krb5_build_principal_ext(context, &mcreds.server,
                                    krb5_princ_realm(context, principal)->length,
                                    krb5_princ_realm(context, principal)->data,
                                    KRB5_TGS_NAME_SIZE, KRB5_TGS_NAME,
                                    krb5_princ_realm(context, principal)->length,
                                    krb5_princ_realm(context, principal)->data,
                                    0);
    if (retval) {
        fprintf(stderr, "Error building TGS principal: %s\n",
                krb5_get_error_message(context, retval));
        goto cleanup;
    }

    // Get credentials from cache
    creds = calloc(1, sizeof(krb5_creds));
    if (!creds) {
        fprintf(stderr, "Memory allocation failed\n");
        goto cleanup;
    }
    
    retval = krb5_cc_retrieve_cred(context, ccache, KRB5_TC_MATCH_SRV_NAMEONLY, 
                                  &mcreds, creds);
    if (retval) {
        fprintf(stderr, "Error retrieving credentials: %s\n",
                krb5_get_error_message(context, retval));
        goto cleanup;
    }

    // Debug information for credentials
    if (creds) {
        printf("Credentials status:\n");
        printf("- Credentials pointer: %p\n", (void*)creds);
        printf("- Ticket length: %u\n", (unsigned int)creds->ticket.length);

        // Decode the ticket
        if (creds->ticket.length > 0) {
            retval = krb5_decode_ticket(&creds->ticket, &ticket);
            if (retval) {
                fprintf(stderr, "Error decoding ticket: %s\n",
                        krb5_get_error_message(context, retval));
            } else {
                printf("Ticket decode status:\n");
                printf("- Decoded ticket pointer: %p\n", (void*)ticket);
                
                // Create and populate enc_part2
                ticket->enc_part2 = calloc(1, sizeof(krb5_enc_tkt_part));
                if (ticket->enc_part2) {
                    memcpy(&ticket->enc_part2->times, &creds->times, sizeof(krb5_ticket_times));
                    ticket->enc_part2->flags = creds->ticket_flags;
                    
                    // Copy the client principal
                    retval = krb5_copy_principal(context, creds->client, &copied_principal);
                    if (retval == 0) {
                        ticket->enc_part2->client = copied_principal;
                    }
                    
                    // Copy session key
                    ticket->enc_part2->session = calloc(1, sizeof(krb5_keyblock));
                    if (ticket->enc_part2->session) {
                        ticket->enc_part2->session->enctype = creds->keyblock.enctype;
                        ticket->enc_part2->session->length = creds->keyblock.length;
                        ticket->enc_part2->session->contents = malloc(creds->keyblock.length);
                        if (ticket->enc_part2->session->contents) {
                            memcpy(ticket->enc_part2->session->contents,
                                   creds->keyblock.contents,
                                   creds->keyblock.length);
                        }
                    }
                }
                
                print_ticket_info(context, ticket);
            }
        }
    }

cleanup:
    if (mcreds.server) krb5_free_principal(context, mcreds.server);
    if (principal) krb5_free_principal(context, principal);
    if (ticket && ticket->enc_part2) {
        if (ticket->enc_part2->session) {
            if (ticket->enc_part2->session->contents) {
                free(ticket->enc_part2->session->contents);
            }
            free(ticket->enc_part2->session);
        }
        if (ticket->enc_part2->client) {
            krb5_free_principal(context, ticket->enc_part2->client);
        }
        free(ticket->enc_part2);
        ticket->enc_part2 = NULL;
    }
    if (ticket) krb5_free_ticket(context, ticket);
    if (creds) krb5_free_creds(context, creds);
    krb5_cc_close(context, ccache);
    krb5_free_context(context);

    return 0;
}
