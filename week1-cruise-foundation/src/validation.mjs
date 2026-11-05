export class InputValidationError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = 'InputValidationError';
    this.status = status;
  }
}

function integerValue(value, label) {
  if (typeof value === 'number' && Number.isSafeInteger(value)) return value;
  if (typeof value === 'string' && /^(0|[1-9]\d*)$/.test(value)) {
    const parsed = Number(value);
    if (Number.isSafeInteger(parsed)) return parsed;
  }
  throw new InputValidationError(`${label} không hợp lệ.`);
}

export function parseId(value, label = 'ID') {
  const parsed = integerValue(value, label);
  if (parsed < 1) throw new InputValidationError(`${label} không hợp lệ.`);
  return parsed;
}

export function parseOptionalId(value, label = 'ID') {
  if (value === undefined || value === null || value === '') return 0;
  return integerValue(value, label);
}

export function parseWhole(value, min, max, label = 'Số') {
  const parsed = integerValue(value, label);
  if (parsed < min || parsed > max) throw new InputValidationError(`${label} không hợp lệ.`);
  return parsed;
}

export function parseAmount(value, label = 'Số tiền') {
  const validNumber = typeof value === 'number' && Number.isFinite(value);
  const validString = typeof value === 'string' && /^(0|[1-9]\d*)(\.\d+)?$/.test(value);
  if ((!validNumber && !validString) || Number(value) < 0 || Number(value) > 1e12) {
    throw new InputValidationError(`${label} không hợp lệ.`);
  }
  return Number(value);
}

export function parseBoolean(value, label = 'Trạng thái') {
  if (typeof value !== 'boolean') throw new InputValidationError(`${label} không hợp lệ.`);
  return value;
}

export function parseText(value, max, label = 'Dữ liệu') {
  if (typeof value !== 'string' || value.length > max || value.includes('\0')) {
    throw new InputValidationError(`${label} không hợp lệ.`);
  }
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(i + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) throw new InputValidationError(`${label} chứa Unicode không hợp lệ.`);
      i++;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      throw new InputValidationError(`${label} chứa Unicode không hợp lệ.`);
    }
  }
  return value;
}
