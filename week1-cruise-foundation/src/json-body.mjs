import {InputValidationError} from './validation.mjs';

export async function readJsonBody(request, maxBytes = 20000) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += bytes.length;
    if (size > maxBytes) throw new InputValidationError('Yêu cầu quá lớn.', 413);
    chunks.push(bytes);
  }

  let raw;
  try {
    raw = new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks));
  } catch {
    throw new InputValidationError('Nội dung JSON phải được mã hóa UTF-8 hợp lệ.');
  }
  if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);

  let body;
  try {
    body = JSON.parse(raw || '{}');
  } catch {
    throw new InputValidationError('JSON không hợp lệ.');
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new InputValidationError('Dữ liệu gửi lên phải là một đối tượng JSON.');
  }
  return body;
}
