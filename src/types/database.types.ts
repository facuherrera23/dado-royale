export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      graphql: {
        Args: {
          extensions?: Json;
          operationName?: string;
          query?: string;
          variables?: Json;
        };
        Returns: Json;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  public: {
    Tables: {
      config: {
        Row: {
          description: string | null;
          key: string;
          value: Json;
        };
        Insert: {
          description?: string | null;
          key: string;
          value: Json;
        };
        Update: {
          description?: string | null;
          key?: string;
          value?: Json;
        };
        Relationships: [];
      };
      house_account: {
        Row: {
          balance: number;
          id: boolean;
          updated_at: string;
        };
        Insert: {
          balance?: number;
          id?: boolean;
          updated_at?: string;
        };
        Update: {
          balance?: number;
          id?: boolean;
          updated_at?: string;
        };
        Relationships: [];
      };
      ledger: {
        Row: {
          amount: number;
          balance_after: number | null;
          created_at: string;
          id: number;
          idempotency_key: string | null;
          round_id: string | null;
          type: Database['public']['Enums']['ledger_type'];
          user_id: string | null;
        };
        Insert: {
          amount: number;
          balance_after?: number | null;
          created_at?: string;
          id?: never;
          idempotency_key?: string | null;
          round_id?: string | null;
          type: Database['public']['Enums']['ledger_type'];
          user_id?: string | null;
        };
        Update: {
          amount?: number;
          balance_after?: number | null;
          created_at?: string;
          id?: never;
          idempotency_key?: string | null;
          round_id?: string | null;
          type?: Database['public']['Enums']['ledger_type'];
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: 'ledger_round_id_fkey';
            columns: ['round_id'];
            isOneToOne: false;
            referencedRelation: 'rounds';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'ledger_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      profiles: {
        Row: {
          avatar_url: string | null;
          country: string | null;
          created_at: string;
          date_of_birth: string | null;
          doc_hash: string | null;
          full_name: string | null;
          id: string;
          is_admin: boolean;
          kyc_at: string | null;
          kyc_verified: boolean;
          username: string;
        };
        Insert: {
          avatar_url?: string | null;
          country?: string | null;
          created_at?: string;
          date_of_birth?: string | null;
          doc_hash?: string | null;
          full_name?: string | null;
          id: string;
          is_admin?: boolean;
          kyc_at?: string | null;
          kyc_verified?: boolean;
          username: string;
        };
        Update: {
          avatar_url?: string | null;
          country?: string | null;
          created_at?: string;
          date_of_birth?: string | null;
          doc_hash?: string | null;
          full_name?: string | null;
          id?: string;
          is_admin?: boolean;
          kyc_at?: string | null;
          kyc_verified?: boolean;
          username?: string;
        };
        Relationships: [];
      };
      round_dealer_holes: {
        Row: {
          cards: number[];
          round_id: string;
        };
        Insert: {
          cards: number[];
          round_id: string;
        };
        Update: {
          cards?: number[];
          round_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'round_dealer_holes_round_id_fkey';
            columns: ['round_id'];
            isOneToOne: true;
            referencedRelation: 'rounds';
            referencedColumns: ['id'];
          },
        ];
      };
      round_players: {
        Row: {
          bet_amount: number;
          card1: number | null;
          card2: number | null;
          cards: number[];
          dice1: number | null;
          dice2: number | null;
          hand_no: number;
          insurance: number | null;
          is_winner: boolean;
          result: string | null;
          round_id: string;
          stood: boolean;
          tiebreak_attempts: number;
          total: number | null;
          user_id: string;
        };
        Insert: {
          bet_amount: number;
          card1?: number | null;
          card2?: number | null;
          cards?: number[];
          dice1?: number | null;
          dice2?: number | null;
          hand_no?: number;
          insurance?: number | null;
          is_winner?: boolean;
          result?: string | null;
          round_id: string;
          stood?: boolean;
          tiebreak_attempts?: number;
          total?: number | null;
          user_id: string;
        };
        Update: {
          bet_amount?: number;
          card1?: number | null;
          card2?: number | null;
          cards?: number[];
          dice1?: number | null;
          dice2?: number | null;
          hand_no?: number;
          insurance?: number | null;
          is_winner?: boolean;
          result?: string | null;
          round_id?: string;
          stood?: boolean;
          tiebreak_attempts?: number;
          total?: number | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'round_players_round_id_fkey';
            columns: ['round_id'];
            isOneToOne: false;
            referencedRelation: 'rounds';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'round_players_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      round_rps_choices: {
        Row: {
          choice: number;
          round_id: string;
          tiebreak_no: number;
          user_id: string;
        };
        Insert: {
          choice: number;
          round_id: string;
          tiebreak_no?: number;
          user_id: string;
        };
        Update: {
          choice?: number;
          round_id?: string;
          tiebreak_no?: number;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'round_rps_choices_round_id_fkey';
            columns: ['round_id'];
            isOneToOne: false;
            referencedRelation: 'rounds';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'round_rps_choices_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      rounds: {
        Row: {
          created_at: string;
          dealer_cards: number[];
          finished_at: string | null;
          house_fee: number;
          id: string;
          pot: number;
          status: Database['public']['Enums']['round_status'];
          table_id: string;
          tiebreak_round: number;
          winner_id: string | null;
        };
        Insert: {
          created_at?: string;
          dealer_cards?: number[];
          finished_at?: string | null;
          house_fee?: number;
          id?: string;
          pot?: number;
          status?: Database['public']['Enums']['round_status'];
          table_id: string;
          tiebreak_round?: number;
          winner_id?: string | null;
        };
        Update: {
          created_at?: string;
          dealer_cards?: number[];
          finished_at?: string | null;
          house_fee?: number;
          id?: string;
          pot?: number;
          status?: Database['public']['Enums']['round_status'];
          table_id?: string;
          tiebreak_round?: number;
          winner_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: 'rounds_table_id_fkey';
            columns: ['table_id'];
            isOneToOne: false;
            referencedRelation: 'tables';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'rounds_winner_id_fkey';
            columns: ['winner_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      table_players: {
        Row: {
          joined_at: string;
          last_action_at: string;
          left_at: string | null;
          pending_bet: number | null;
          status: Database['public']['Enums']['table_player_status'];
          table_id: string;
          user_id: string;
        };
        Insert: {
          joined_at?: string;
          last_action_at?: string;
          left_at?: string | null;
          pending_bet?: number | null;
          status?: Database['public']['Enums']['table_player_status'];
          table_id: string;
          user_id: string;
        };
        Update: {
          joined_at?: string;
          last_action_at?: string;
          left_at?: string | null;
          pending_bet?: number | null;
          status?: Database['public']['Enums']['table_player_status'];
          table_id?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'table_players_table_id_fkey';
            columns: ['table_id'];
            isOneToOne: false;
            referencedRelation: 'tables';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'table_players_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      tables: {
        Row: {
          bet_amount: number;
          created_at: string;
          game: string;
          id: string;
          max_bet: number | null;
          max_players: number;
          name: string;
          status: Database['public']['Enums']['table_status'];
        };
        Insert: {
          bet_amount: number;
          created_at?: string;
          game?: string;
          id?: string;
          max_bet?: number | null;
          max_players: number;
          name: string;
          status?: Database['public']['Enums']['table_status'];
        };
        Update: {
          bet_amount?: number;
          created_at?: string;
          game?: string;
          id?: string;
          max_bet?: number | null;
          max_players?: number;
          name?: string;
          status?: Database['public']['Enums']['table_status'];
        };
        Relationships: [];
      };
      wallets: {
        Row: {
          balance: number;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          balance?: number;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          balance?: number;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'wallets_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: true;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      _roll_round_dice_poker: { Args: { p_round_id: string }; Returns: Json };
      _roll_round_war: { Args: { p_round_id: string }; Returns: Json };
      _uniform: { Args: { p_max: number }; Returns: number };
      bj_action: {
        Args: { p_action: string; p_hand?: number; p_round_id: string };
        Returns: Json;
      };
      cancel_round: { Args: { p_round_id: string }; Returns: Json };
      cancel_stale_rounds: { Args: never; Returns: number };
      card_rank: { Args: { p_card: number }; Returns: number };
      card_value: { Args: { p_card: number }; Returns: number };
      claim_faucet: { Args: never; Returns: Json };
      config_int: { Args: { p_key: string }; Returns: number };
      draw_card: { Args: { p_round: string }; Returns: number };
      get_admin_stats: { Args: never; Returns: Json };
      get_leaderboard: {
        Args: { p_game?: string; p_limit?: number };
        Returns: {
          rounds_won: number;
          total_won: number;
          username: string;
        }[];
      };
      get_my_stats: { Args: never; Returns: Json };
      hand_score: { Args: { p_c1: number; p_c2: number }; Returns: number };
      hand_value: { Args: { p_cards: number[] }; Returns: number };
      is_admin: { Args: { p_uid?: string }; Returns: boolean };
      is_blackjack: { Args: { p_cards: number[] }; Returns: boolean };
      join_table: { Args: { p_table_id: string }; Returns: Json };
      leave_table: { Args: { p_table_id: string }; Returns: Json };
      roll_d6: { Args: never; Returns: number };
      roll_round: { Args: { p_round_id: string }; Returns: Json };
      rps_play: {
        Args: { p_choice: number; p_round_id: string };
        Returns: Json;
      };
      set_bet: { Args: { p_amount: number; p_table_id: string }; Returns: Json };
      start_round: { Args: { p_table_id: string }; Returns: Json };
      submit_kyc: {
        Args: {
          p_country: string;
          p_dob: string;
          p_doc_id: string;
          p_full_name: string;
        };
        Returns: Json;
      };
    };
    Enums: {
      ledger_type:
        | 'faucet'
        | 'bet_lock'
        | 'payout'
        | 'refund'
        | 'house_fee'
        | 'adjustment'
        | 'house_settlement';
      round_status: 'waiting' | 'in_progress' | 'finished' | 'cancelled';
      table_player_status: 'seated' | 'left';
      table_status: 'open' | 'in_round' | 'closed';
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      ledger_type: [
        'faucet',
        'bet_lock',
        'payout',
        'refund',
        'house_fee',
        'adjustment',
        'house_settlement',
      ],
      round_status: ['waiting', 'in_progress', 'finished', 'cancelled'],
      table_player_status: ['seated', 'left'],
      table_status: ['open', 'in_round', 'closed'],
    },
  },
} as const;
