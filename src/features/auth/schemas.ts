import { z } from 'zod';

export const loginSchema = z.object({
  email: z.email('Introduce un email válido'),
  password: z.string().min(1, 'Introduce tu contraseña'),
});

export const registerSchema = z
  .object({
    username: z
      .string()
      .regex(/^[a-zA-Z0-9_]{3,20}$/, '3–20 caracteres: letras, números y guion bajo'),
    email: z.email('Introduce un email válido'),
    password: z
      .string()
      .min(8, 'Mínimo 8 caracteres')
      .regex(/[a-zA-Z]/, 'Debe incluir al menos una letra')
      .regex(/[0-9]/, 'Debe incluir al menos un número'),
    confirmPassword: z.string(),
    acceptAdult: z.literal(true, {
      error: 'Debes confirmar que eres mayor de 18 años',
    }),
    acceptTerms: z.literal(true, {
      error: 'Debes aceptar los términos y condiciones',
    }),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: 'Las contraseñas no coinciden',
    path: ['confirmPassword'],
  });

export type LoginInput = z.infer<typeof loginSchema>;
export type RegisterInput = z.infer<typeof registerSchema>;
