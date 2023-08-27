package common

import (
	"bytes"
	"crypto/cipher"
	"crypto/des"
	"encoding/base64"
)

func Decrypt3Des(text, key, iv string) (string, error) {
	block, err := des.NewTripleDESCipher([]byte(key))
	if err != nil {
		return "", err
	}
	decrypter := cipher.NewCBCDecrypter(block, []byte(iv))

	decoded, err := base64.StdEncoding.DecodeString(text)
	if err != nil {
		return "", err
	}

	decrypted := make([]byte, len(decoded))
	decrypter.CryptBlocks(decrypted, decoded)
	decrypted = pkcs7UnPadding(decrypted, block.BlockSize())

	return string(decrypted), nil
}

func Encrypt3Des(text, key, iv string) (string, error) {
	block, err := des.NewTripleDESCipher([]byte(key))
	if err != nil {
		return "", err
	}
	encrypter := cipher.NewCBCEncrypter(block, []byte(iv))

	src := pkcs7Padding([]byte(text), block.BlockSize())
	encrypted := make([]byte, len(src))
	encrypter.CryptBlocks(encrypted, src)

	output := base64.StdEncoding.EncodeToString(encrypted)

	return output, nil
}

func pkcs7Padding(data []byte, blockSize int) []byte {
	padLen := blockSize - len(data)%blockSize
	padding := bytes.Repeat([]byte{byte(padLen)}, padLen)
	return append(data, padding...)
}

func pkcs7UnPadding(data []byte, blockSize int) []byte {
	length := len(data)
	if length == 0 {
		return nil
	}
	if length%blockSize != 0 {
		return nil
	}

	padLen := int(data[length-1])
	ref := bytes.Repeat([]byte{byte(padLen)}, padLen)
	if padLen > blockSize || padLen == 0 || !bytes.HasSuffix(data, ref) {
		return nil
	}
	return data[:length-padLen]
}
