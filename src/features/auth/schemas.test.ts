import { describe, expect, it } from 'vitest';

import { loginSchema, registerSchema } from './schemas';

const validRegister = {
  username: 'jugador_1',
  email: 'test@example.com',
  password: 'clave1234',
  confirmPassword: 'clave1234',
  acceptAdult: true,
  acceptTerms: true,
} as const;

describe('schemas de auth', () => {
  it('acepta un registro válido', () => {
    expect(registerSchema.safeParse(validRegister).success).toBe(true);
  });

  it('rechaza username con formato inválido', () => {
    const r = registerSchema.safeParse({ ...validRegister, username: 'mal nombre!' });
    expect(r.success).toBe(false);
    if (!r.success) {
      expect(r.error.issues.some((i) => i.path[0] === 'username')).toBe(true);
    }
  });

  it('rechaza contraseña sin números', () => {
    const r = registerSchema.safeParse({
      ...validRegister,
      password: 'solo-letras',
      confirmPassword: 'solo-letras',
    });
    expect(r.success).toBe(false);
  });

  it('rechaza contraseñas que no coinciden', () => {
    const r = registerSchema.safeParse({ ...validRegister, confirmPassword: 'otra1234' });
    expect(r.success).toBe(false);
    if (!r.success) {
      expect(r.error.issues.some((i) => i.path[0] === 'confirmPassword')).toBe(true);
    }
  });

  it('exige confirmar mayoría de edad y términos', () => {
    const sinAdult = registerSchema.safeParse({ ...validRegister, acceptAdult: false });
    const sinTerms = registerSchema.safeParse({ ...validRegister, acceptTerms: false });
    expect(sinAdult.success).toBe(false);
    expect(sinTerms.success).toBe(false);
  });

  it('acepta un login válido y rechaza email inválido', () => {
    expect(loginSchema.safeParse({ email: 'a@b.com', password: 'x' }).success).toBe(true);
    expect(loginSchema.safeParse({ email: 'no-es-email', password: 'x' }).success).toBe(false);
  });
});
